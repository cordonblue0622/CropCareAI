import 'dart:async';
import 'dart:io';

import 'package:cropcare_ai/core/constants/app_constants.dart';
import 'package:cropcare_ai/core/constants/app_enums.dart';
import 'package:cropcare_ai/core/utils/image_reference.dart';
import 'package:cropcare_ai/data/local/database_helper.dart';
import 'package:cropcare_ai/data/local/bundled_disease_knowledge.dart';
import 'package:cropcare_ai/data/models/chat_message_model.dart';
import 'package:cropcare_ai/data/models/chat_session_model.dart';
import 'package:cropcare_ai/data/models/crop_model.dart';
import 'package:cropcare_ai/data/models/diagnosis_model.dart';
import 'package:cropcare_ai/data/models/progress_update_model.dart';
import 'package:cropcare_ai/data/models/treatment_model.dart';
import 'package:cropcare_ai/data/models/treatment_task_model.dart';
import 'package:cropcare_ai/data/remote/ai_backend_service.dart';
import 'package:cropcare_ai/data/remote/supabase_service.dart';
import 'package:cropcare_ai/features/chat/providers/chat_provider.dart';
import 'package:cropcare_ai/features/crops/providers/crops_provider.dart';
import 'package:cropcare_ai/services/connectivity_service.dart';
import 'package:cropcare_ai/services/local_classifier_service.dart';
import 'package:cropcare_ai/services/sync_service.dart';
import 'package:cropcare_ai/services/tflite_classifier_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

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

class _DelayedKnowledgeSupabaseService extends _OfflineSupabaseService {
  final Completer<List<Map<String, dynamic>>> pendingKnowledge = Completer();

  @override
  Future<List<Map<String, dynamic>>> getDiseaseKnowledge({
    String? cropType,
  }) =>
      pendingKnowledge.future;
}

class _DelayedCropFetchSupabaseService extends _OfflineSupabaseService {
  final pendingCrops = Completer<List<Map<String, dynamic>>>();

  @override
  Future<List<Map<String, dynamic>>> getCropsIncludingDeleted(
    String userId,
  ) =>
      pendingCrops.future;
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
      cropType: 'tomato',
      detections: [
        AiBackendDetectionItem(
          label: 'Tomato Early Blight',
          labelKey: 'tomato_early_blight',
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

  var syncCalls = 0;

  @override
  Future<void> syncAll() async {
    syncCalls++;
  }
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
      diseaseName: 'Tomato Early Blight',
      labelKey: 'tomato_early_blight',
      cropName: 'Offline tomato',
      cropType: CropType.tomato,
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

  test('scan disease lookup returns bundled knowledge before remote refresh',
      () async {
    final supabase = _DelayedKnowledgeSupabaseService();
    final provider = CropsProvider(
      supabase: supabase,
      db: database,
      sync: _NoopSyncService(
        supabaseService: supabase,
        dbHelper: database,
      ),
    );
    addTearDown(provider.dispose);

    final knowledge = await provider
        .fetchDiseaseKnowledge(cropType: CropType.tomato.value)
        .timeout(const Duration(seconds: 2));

    expect(
      knowledge.any((item) => item.labelKey == 'tomato_early_blight'),
      isTrue,
    );
    expect(supabase.pendingKnowledge.isCompleted, isFalse);
    supabase.pendingKnowledge.complete(const []);
  });

  test('My Crops renders the SQLite snapshot before remote refresh completes',
      () async {
    final supabase = _DelayedCropFetchSupabaseService();
    final provider = CropsProvider(
      supabase: supabase,
      db: database,
      sync: _NoopSyncService(
        supabaseService: supabase,
        dbHelper: database,
      ),
    );
    addTearDown(provider.dispose);
    final now = DateTime.utc(2026, 10, 31, 13);
    final crop = CropModel(
      id: 'crop-local-only',
      userId: 'offline-user',
      cropType: CropType.tomato,
      cropName: 'Saved while offline',
      createdAt: now,
      updatedAt: now,
    );
    await database.upsertRow(AppConstants.cropsTable, crop.toMap());

    final localReady = Completer<void>();
    provider.addListener(() {
      if (!provider.isLoading &&
          provider.crops.isNotEmpty &&
          !localReady.isCompleted) {
        localReady.complete();
      }
    });
    final refresh = provider.fetchCrops(crop.userId);
    await localReady.future.timeout(const Duration(seconds: 2));
    expect(provider.isLoading, isFalse);
    expect(provider.crops.single.id, crop.id);
    expect(supabase.pendingCrops.isCompleted, isFalse);

    supabase.pendingCrops.complete(const []);
    await refresh;
    expect(provider.crops.single.id, crop.id);
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
      connectivity: _OfflineConnectivityService(),
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
    expect(metadata['result_label'], 'Tomato Early Blight');
    expect(metadata['model_version'], '1');
    expect(metadata['detected_regions_json'], isA<Map>());

    final syncCallsBeforeSave = sync.syncCalls;
    final cropId = await crops.addCropFromDiagnosis(
      userId: 'offline-user',
      diseaseName: metadata['disease_name'] as String,
      labelKey: metadata['label_key'] as String,
      cropName: 'Offline tomato',
      cropType: CropType.tomato,
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
      diagnosisId: metadata['diagnosis_id'] as String,
      diagnosedAt: DateTime.parse(metadata['diagnosed_at'] as String),
      chatSessionId: chat.currentSession!.id,
    );
    expect(cropId, isNotNull);
    expect(sync.syncCalls, syncCallsBeforeSave);
    await chat.linkCurrentSessionToCrop(cropId!);

    final taskBeforeRestart = TreatmentTaskModel.fromMap(
      (await database.queryAllTasksForCrop(cropId)).first,
    );
    final completedTask = await crops.markTaskDone(
      taskBeforeRestart.id,
      recomputeHealthScore: false,
      syncNow: false,
    );
    expect(completedTask?.status, TaskStatus.completed);
    final now = DateTime.now();
    await crops.saveProgressUpdate(
      ProgressUpdateModel(
        id: 'progress-offline-restart',
        cropId: cropId,
        treatmentId: taskBeforeRestart.treatmentId,
        diagnosisId: metadata['diagnosis_id'] as String,
        userId: 'offline-user',
        note: 'Offline daily submission with completed work.',
        imageUrl: buildInlineImageDataUrl(const [1, 2, 3]),
        completedTaskCount: 1,
        updateDate: now,
        aiAnalysisStatus: AiAnalysisStatus.pending,
        createdAt: now,
        updatedAt: now,
      ),
      syncNow: false,
    );

    await database.closeDatabase();

    final crop = await database.queryById(AppConstants.cropsTable, cropId);
    expect(crop?['crop_name'], 'Offline tomato');
    final diagnosis = DiagnosisModel.fromMap(
      (await database.queryDiagnosesForCrop(cropId)).single,
    );
    expect(diagnosis.cropId, cropId);
    expect(diagnosis.chatSessionId, chat.currentSession!.id);
    expect(diagnosis.id, metadata['diagnosis_id']);
    expect(diagnosis.diagnosedAt.toIso8601String(), metadata['diagnosed_at']);
    expect(diagnosis.diseaseName, 'Tomato Early Blight');
    expect(diagnosis.confidenceScore, 0.91);
    expect(diagnosis.resultLabel, 'Tomato Early Blight');
    expect(diagnosis.modelName, 'test-tflite');
    expect(diagnosis.modelVersion, '1');
    expect(diagnosis.summary, contains('Tomato Early Blight'));
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
      expect(task.description?.trim(), isNotEmpty);
    }
    final persistedCompletedTask = tasks.singleWhere(
      (task) => task.id == taskBeforeRestart.id,
    );
    expect(persistedCompletedTask.status, TaskStatus.completed);
    expect(persistedCompletedTask.completedAt, isNotNull);
    final persistedProgress = ProgressUpdateModel.fromMap(
      (await database.queryProgressUpdatesForCrop(cropId)).single,
    );
    expect(persistedProgress.note, contains('Offline daily submission'));
    expect(persistedProgress.completedTaskCount, 1);
    expect(persistedProgress.aiAnalysisStatus, AiAnalysisStatus.pending);
    expect(persistedProgress.imageUrl, startsWith('data:image/'));

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
      contains('Tomato Early Blight'),
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
        AppConstants.progressUpdatesTable,
        AppConstants.chatSessionsTable,
        AppConstants.chatMessagesTable,
      ]),
    );
  });

  test('actual offline TFLite result persists with its local crop plan',
      () async {
    final modelBytes = await File(
      'assets/models/plant_disease_efficientnetv2s.tflite',
    ).readAsBytes();
    final imageBytes = await File(
      'test/fixtures/tflite/tomato.jpg',
    ).readAsBytes();
    final labels = (await File(
      'assets/models/plant_disease_efficientnetv2s_labels.txt',
    ).readAsString())
        .split('\n')
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList(growable: false);
    final interpreter = Interpreter.fromBuffer(modelBytes);
    addTearDown(interpreter.close);

    final result = const TfliteClassifierCore().classifyImage(
      imageBytes: imageBytes,
      filename: 'tomato.jpg',
      interpreter: interpreter,
      labels: labels,
      cropType: CropType.tomato.value,
      modelName: 'plant_disease_efficientnetv2s',
      modelVersion: 'cropcare-24-efficientnetv2s-float16',
    );
    expect(result.status, 'ok');
    expect(result.cropType, CropType.tomato.value);
    final prediction = result.primaryDetection!;

    final supabase = _OfflineSupabaseService();
    final sync = _NoopSyncService(
      supabaseService: supabase,
      dbHelper: database,
    );
    final crops = CropsProvider(
      supabase: supabase,
      db: database,
      sync: sync,
      connectivity: _OfflineConnectivityService(),
    );
    addTearDown(crops.dispose);
    final knowledge = BundledDiseaseKnowledge.records(
      cropType: CropType.tomato.value,
    ).singleWhere(
      (record) => record.labelKey == prediction.labelKey,
    );
    expect(knowledge.treatmentSteps, isNotEmpty);

    final cropId = await crops.addCropFromDiagnosis(
      userId: 'offline-user',
      diseaseName: prediction.label,
      labelKey: prediction.labelKey!,
      cropName: 'Offline model tomato',
      cropType: CropType.tomato,
      severity: Severity.moderate,
      treatmentSteps: knowledge.treatmentSteps!,
      initialSummary: knowledge.description,
      confidenceScore: prediction.confidence,
      resultLabel: prediction.label,
      modelName: result.model.name,
      modelVersion: result.model.version,
      imageUrl: buildInlineImageDataUrl(imageBytes),
      diagnosisMode: DiagnosisMode.offline,
      diagnosisId: 'offline-tflite-diagnosis',
      diagnosedAt: DateTime.utc(2026, 11, 2, 9),
    );
    expect(cropId, isNotNull);

    await database.closeDatabase();

    final crop = await database.queryById(AppConstants.cropsTable, cropId!);
    final diagnosis = DiagnosisModel.fromMap(
      (await database.queryDiagnosesForCrop(cropId)).single,
    );
    final treatments = await database.queryTreatmentsForCrop(cropId);
    final tasks = await database.queryAllTasksForCrop(cropId);

    expect(crop?['crop_name'], 'Offline model tomato');
    expect(crop?['crop_type'], CropType.tomato.value);
    expect(diagnosis.diagnosisMode, DiagnosisMode.offline);
    expect(diagnosis.labelKey, prediction.labelKey);
    expect(diagnosis.confidenceScore, closeTo(prediction.confidence, 0.0001));
    expect(diagnosis.diagnosedAt, DateTime.utc(2026, 11, 2, 9));
    expect(diagnosis.imageUrl, buildInlineImageDataUrl(imageBytes));
    expect(diagnosis.summary, knowledge.description);
    expect(treatments, hasLength(1));
    expect(tasks, isNotEmpty);
  });

  test('crop detail can restore related records from its saved offline card',
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

    final now = DateTime(2026, 11, 1, 9);
    final crop = CropModel(
      id: 'crop-recovery',
      userId: 'offline-user',
      cropType: CropType.tomato,
      cropName: 'Offline tomato',
      createdAt: now,
      updatedAt: now,
    );
    final session = ChatSessionModel(
      id: 'session-recovery',
      userId: crop.userId,
      cropId: crop.id,
      isOfflineSession: true,
      createdAt: now,
      updatedAt: now,
    );
    final card = ChatMessageModel(
      id: 'diagnosis-recovery',
      sessionId: session.id,
      userId: crop.userId,
      role: MessageRole.system,
      content: '',
      metadata: {
        'type': 'add_crop_suggestion',
        'diagnosis_id': 'diagnosis-recovery',
        'diagnosed_at': now.toIso8601String(),
        'diagnosis_mode': DiagnosisMode.offline.value,
        'crop_type': CropType.tomato.value,
        'disease_name': 'Tomato Early Blight',
        'label_key': 'tomato_early_blight',
        'severity': Severity.moderate.value,
        'summary': 'Offline TFLite result: Tomato Early Blight.',
        'confidence_score': 0.88,
        'result_label': 'Tomato Early Blight',
        'model_name': 'plant_disease_efficientnetv2s',
        'model_version': 'cropcare-24-efficientnetv2s-float16',
        'image_url': 'data:image/jpeg;base64,AQID',
        'recommended_actions': [
          'Remove infected lower leaves as soon as you see them.',
          'Inspect the plant for new spots each day.',
        ],
      },
      createdAt: now,
    );
    await database.upsertRows(AppConstants.cropsTable, [crop.toMap()]);
    await database.upsertRows(
      AppConstants.chatSessionsTable,
      [session.toMap()],
    );
    await database.upsertRows(AppConstants.chatMessagesTable, [card.toMap()]);
    // Reproduce the old partial save: the diagnosis row exists, but its
    // associated metadata was never committed. Recovery must enrich it.
    await database.upsertRows(AppConstants.diagnosesTable, [
      DiagnosisModel(
        id: 'diagnosis-recovery',
        cropId: crop.id,
        userId: crop.userId,
        diagnosisMode: DiagnosisMode.offline,
        diseaseName: 'Tomato Early Blight',
        diagnosedAt: now,
        createdAt: now,
        updatedAt: now,
      ).toMap(),
    ]);

    final localSessions = (await database.queryChatSessionsByCrop(crop.id))
        .map(ChatSessionModel.fromMap)
        .toList();
    final localMessages = (await database.queryChatMessages(session.id))
        .map(ChatMessageModel.fromMap)
        .toList();
    expect(
      await provider.restoreCropDiagnosisFromLocalSuggestion(
        crop: crop,
        sessions: localSessions,
        messages: localMessages,
      ),
      isTrue,
    );

    await database.closeDatabase();
    final diagnosis = DiagnosisModel.fromMap(
      (await database.queryDiagnosesForCrop(crop.id)).single,
    );
    expect(diagnosis.id, 'diagnosis-recovery');
    expect(diagnosis.cropId, crop.id);
    expect(diagnosis.chatSessionId, session.id);
    expect(diagnosis.diagnosisMode, DiagnosisMode.offline);
    expect(diagnosis.summary, contains('Offline TFLite result'));
    expect(diagnosis.imageUrl, 'data:image/jpeg;base64,AQID');

    final treatment = TreatmentModel.fromMap(
      (await database.queryTreatmentsForCrop(crop.id)).single,
    );
    expect(treatment.diagnosisId, diagnosis.id);
    expect(treatment.treatmentSteps,
        contains('Inspect the plant for new spots each day.'));
    final tasks = (await database.queryAllTasksForCrop(crop.id))
        .map(TreatmentTaskModel.fromMap)
        .toList();
    expect(tasks, isNotEmpty);
    expect(tasks.every((task) => task.treatmentId == treatment.id), isTrue);
    expect(tasks.every((task) => task.cropId == crop.id), isTrue);
    expect(
        await provider.restoreCropDiagnosisFromLocalSuggestion(
          crop: crop,
          sessions: localSessions,
          messages: localMessages,
        ),
        isFalse);
  });
}
