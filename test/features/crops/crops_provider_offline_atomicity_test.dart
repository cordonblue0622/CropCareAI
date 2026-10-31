import 'package:cropcare_ai/core/constants/app_constants.dart';
import 'package:cropcare_ai/core/constants/app_enums.dart';
import 'package:cropcare_ai/data/local/database_helper.dart';
import 'package:cropcare_ai/data/models/ai_backend_models.dart';
import 'package:cropcare_ai/data/models/chat_message_model.dart';
import 'package:cropcare_ai/data/models/diagnosis_model.dart';
import 'package:cropcare_ai/data/models/treatment_model.dart';
import 'package:cropcare_ai/data/models/treatment_task_model.dart';
import 'package:cropcare_ai/data/remote/ai_backend_service.dart';
import 'package:cropcare_ai/data/remote/supabase_service.dart';
import 'package:cropcare_ai/features/chat/providers/chat_provider.dart';
import 'package:cropcare_ai/features/crops/providers/crops_provider.dart';
import 'package:cropcare_ai/services/connectivity_service.dart';
import 'package:cropcare_ai/services/local_classifier_service.dart';
import 'package:cropcare_ai/services/sync_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _OfflineSupabaseService extends SupabaseService {
  @override
  Future<List<Map<String, dynamic>>> getDiseaseKnowledge({
    String? cropType,
  }) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> getDiseaseTreatmentDaySteps(
    String diseaseKnowledgeBaseId,
  ) async =>
      const [];
}

class _OfflineConnectivityService extends ConnectivityService {
  @override
  Future<bool> get isConnected async => false;
}

class _FakeLocalClassifierService extends LocalClassifierService {
  @override
  Future<AiBackendDetectResponse> classifyImage({
    required List<int> imageBytes,
    required String filename,
    String? cropType,
  }) async {
    return const AiBackendDetectResponse(
      status: 'ok',
      source: 'local-tflite',
      cropType: 'eggplant',
      detections: [
        AiBackendDetectionItem(
          label: 'Eggplant Leaf Spot',
          labelKey: 'eggplant_leaf_spot',
          confidence: 0.91,
          bbox: AiBackendBoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
        ),
      ],
      model: AiBackendModelInfo(name: 'test-tflite', version: '1'),
      notes: ['offline test detection'],
    );
  }
}

class _NoopSyncService extends SyncService {
  _NoopSyncService({
    required super.supabaseService,
    required super.dbHelper,
  });

  @override
  Future<void> syncAll() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const connectivityChannel =
      MethodChannel('dev.fluttercommunity.plus/connectivity');
  late DatabaseHelper database;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (_) async => <String>[]);
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null);
  });

  setUp(() async {
    database = DatabaseHelper.instance;
    await database.deleteDatabaseFile();
  });

  tearDown(() => database.deleteDatabaseFile());

  test('a related-record failure rolls back the whole diagnosed crop',
      () async {
    final supabase = _OfflineSupabaseService();
    final provider = CropsProvider(
      supabase: supabase,
      db: database,
      sync: _NoopSyncService(
        supabaseService: supabase,
        dbHelper: database,
      ),
    );
    addTearDown(provider.dispose);

    final db = await database.database;
    await db.execute('''
      CREATE TRIGGER reject_treatment_insert
      BEFORE INSERT ON ${AppConstants.treatmentsTable}
      BEGIN
        SELECT RAISE(ABORT, 'simulated treatment write failure');
      END
    ''');

    final cropId = await provider.addCropFromDiagnosis(
      userId: 'offline-user',
      diseaseName: 'Eggplant Leaf Spot',
      labelKey: 'eggplant_leaf_spot',
      cropName: 'Offline eggplant',
      cropType: CropType.eggplant,
      severity: Severity.moderate,
      treatmentSteps: const ['Inspect leaves daily for new spots.'],
      initialSummary: 'Preliminary offline result.',
      confidenceScore: 0.91,
      diagnosisMode: DiagnosisMode.offline,
    );

    expect(cropId, isNull);
    expect(provider.error, contains('simulated treatment write failure'));
    await database.closeDatabase();

    expect(
      await database.queryByUserId(AppConstants.cropsTable, 'offline-user'),
      isEmpty,
    );
    expect(
      await database.queryByUserId(AppConstants.diagnosesTable, 'offline-user'),
      isEmpty,
    );
    expect(
      await database.queryByUserId(
        AppConstants.treatmentTasksTable,
        'offline-user',
      ),
      isEmpty,
    );
    expect(await database.getPendingSyncItems(), isEmpty);
    expect(provider.crops, isEmpty);
  });

  test('offline detection crop and conversations survive a database restart',
      () async {
    final supabase = _OfflineSupabaseService();
    final sync = _NoopSyncService(
      supabaseService: supabase,
      dbHelper: database,
    );
    final chat = ChatProvider(
      supabase: supabase,
      db: database,
      aiBackend: AiBackendService(supabase: supabase),
      connectivity: _OfflineConnectivityService(),
      sync: sync,
      localClassifier: _FakeLocalClassifierService(),
    );
    final crops = CropsProvider(
      supabase: supabase,
      db: database,
      sync: sync,
    );
    addTearDown(chat.dispose);
    addTearDown(crops.dispose);

    await chat.sendMessage(
      userId: 'offline-user',
      content: 'Please analyze this crop photo.',
      attachedImageBytes: const [1, 2, 3],
    );

    expect(chat.currentSession?.isOfflineSession, isTrue);
    expect(chat.currentMessages, hasLength(3));
    final card = chat.currentMessages.singleWhere(
      (message) => message.metadata?['type'] == 'add_crop_suggestion',
    );
    final metadata = card.metadata!;
    expect(metadata['confidence_score'], 0.91);
    expect(metadata['result_label'], 'Eggplant Leaf Spot');
    expect(metadata['model_version'], '1');
    expect(metadata['detected_regions_json'], isA<Map>());

    final cropId = await crops.addCropFromDiagnosis(
      userId: 'offline-user',
      diseaseName: metadata['disease_name'] as String,
      labelKey: metadata['label_key'] as String,
      cropName: 'Offline eggplant',
      cropType: CropType.eggplant,
      severity: SeverityX.fromValue(metadata['severity'] as String),
      treatmentSteps: (metadata['recommended_actions'] as List)
          .map((step) => step.toString())
          .toList(),
      initialSummary: metadata['summary'] as String,
      confidenceScore: (metadata['confidence_score'] as num).toDouble(),
      resultLabel: metadata['result_label'] as String,
      modelName: metadata['model_name'] as String,
      modelVersion: metadata['model_version'] as String,
      imageUrl: metadata['image_url'] as String,
      detectedRegionsJson: Map<String, dynamic>.from(
        metadata['detected_regions_json'] as Map,
      ),
      diagnosisMode: DiagnosisMode.offline,
      chatSessionId: chat.currentSession!.id,
    );
    expect(cropId, isNotNull);
    await chat.linkCurrentSessionToCrop(cropId!);

    await database.closeDatabase();

    final crop = await database.queryById(AppConstants.cropsTable, cropId);
    expect(crop?['crop_name'], 'Offline eggplant');
    final diagnosis = DiagnosisModel.fromMap(
      (await database.queryDiagnosesForCrop(cropId)).single,
    );
    expect(diagnosis.cropId, cropId);
    expect(diagnosis.chatSessionId, chat.currentSession!.id);
    expect(diagnosis.diseaseName, 'Eggplant Leaf Spot');
    expect(diagnosis.confidenceScore, 0.91);
    expect(diagnosis.resultLabel, 'Eggplant Leaf Spot');
    expect(diagnosis.modelName, 'test-tflite');
    expect(diagnosis.modelVersion, '1');
    expect(diagnosis.summary, contains('Eggplant Leaf Spot'));
    expect(diagnosis.imageUrl, startsWith('data:image/'));
    expect(diagnosis.detectedRegionsJson?['source'], 'local-tflite');
    expect(diagnosis.diagnosisMode, DiagnosisMode.offline);

    final treatment = TreatmentModel.fromMap(
      (await database.queryTreatmentsForCrop(cropId)).single,
    );
    expect(treatment.cropId, cropId);
    expect(treatment.diagnosisId, diagnosis.id);
    expect(treatment.diseaseName, diagnosis.diseaseName);
    expect(treatment.treatmentSteps, isNotEmpty);
    final tasks = (await database.queryAllTasksForCrop(cropId))
        .map(TreatmentTaskModel.fromMap)
        .toList();
    expect(tasks, isNotEmpty);
    for (final task in tasks) {
      expect(task.cropId, cropId);
      expect(task.treatmentId, treatment.id);
      expect(task.title, isNotEmpty);
    }

    final sessions = await database.queryChatSessionsByCrop(cropId);
    expect(sessions, hasLength(1));
    expect(sessions.single['is_offline_session'], 1);
    final messages = (await database.queryChatMessages(chat.currentSession!.id))
        .map(ChatMessageModel.fromMap)
        .toList();
    expect(messages, hasLength(3));
    expect(
      messages.map((message) => message.role).toSet(),
      containsAll(
          [MessageRole.user, MessageRole.assistant, MessageRole.system]),
    );
    expect(
      messages
          .singleWhere((message) => message.role == MessageRole.assistant)
          .content,
      contains('Eggplant Leaf Spot'),
    );
    final persistedCard = messages.singleWhere(
      (message) => message.metadata?['type'] == 'add_crop_suggestion',
    );
    expect(persistedCard.metadata?['confidence_score'], 0.91);

    final queuedTables = (await database.getPendingSyncItems())
        .map((item) => item['table_name'])
        .toSet();
    expect(
      queuedTables,
      containsAll([
        AppConstants.cropsTable,
        AppConstants.diagnosesTable,
        AppConstants.treatmentsTable,
        AppConstants.treatmentTasksTable,
        AppConstants.chatSessionsTable,
        AppConstants.chatMessagesTable,
      ]),
    );
  });
}
