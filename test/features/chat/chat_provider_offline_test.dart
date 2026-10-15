import 'package:cropcare_ai/core/constants/app_constants.dart';
import 'package:cropcare_ai/core/constants/app_enums.dart';
import 'package:cropcare_ai/data/local/database_helper.dart';
import 'package:cropcare_ai/data/models/diagnosis_model.dart';
import 'package:cropcare_ai/data/remote/ai_backend_service.dart';
import 'package:cropcare_ai/data/remote/supabase_service.dart';
import 'package:cropcare_ai/features/chat/providers/chat_provider.dart';
import 'package:cropcare_ai/services/connectivity_service.dart';
import 'package:cropcare_ai/services/local_classifier_service.dart';
import 'package:cropcare_ai/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _OfflineConnectivityService extends ConnectivityService {
  @override
  Future<bool> get isConnected async => false;
}

class _OnlineConnectivityService extends ConnectivityService {
  @override
  Future<bool> get isConnected async => true;
}

class _FakeSupabaseService extends SupabaseService {
  @override
  Future<List<Map<String, dynamic>>> getDiseaseKnowledge({
    String? cropType,
  }) async =>
      const [];

  @override
  Future<void> insertChatMessage(Map<String, dynamic> message) async {}

  @override
  Future<void> upsertChatSession(Map<String, dynamic> session) async {}

  @override
  Future<String?> uploadChatImage({
    required String userId,
    required String messageId,
    required List<int> bytes,
  }) async =>
      null;
}

class _NoopSyncService extends SyncService {
  _NoopSyncService({
    required super.supabaseService,
    required super.dbHelper,
  });

  @override
  Future<void> pushPendingChanges() async {}
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
          label: 'Eggplant Healthy',
          labelKey: 'eggplant_healthy',
          confidence: 0.91,
          bbox: AiBackendBoundingBox(x: 0, y: 0, width: 1, height: 1),
        ),
      ],
      model: AiBackendModelInfo(name: 'test-tflite', version: '1'),
      notes: [],
    );
  }
}

class _UncertainLocalClassifierService extends LocalClassifierService {
  @override
  Future<AiBackendDetectResponse> classifyImage({
    required List<int> imageBytes,
    required String filename,
    String? cropType,
  }) async {
    return const AiBackendDetectResponse(
      status: 'no_match',
      source: 'local-tflite',
      cropType: 'eggplant',
      detections: [
        AiBackendDetectionItem(
          label: 'Eggplant Leaf Spot',
          labelKey: 'eggplant_leaf_spot',
          confidence: 0.54,
          bbox: AiBackendBoundingBox(x: 0, y: 0, width: 1, height: 1),
        ),
      ],
      model: AiBackendModelInfo(name: 'test-tflite', version: '1'),
      notes: [],
    );
  }
}

class _TrackingAiBackendService extends AiBackendService {
  _TrackingAiBackendService({required super.supabase});

  int sendCallCount = 0;
  String? lastCropId;
  String? lastHintCropType;
  AiBackendChatResponse response = const AiBackendChatResponse(
    answer: 'The image shows eggplant.',
    recommendedActions: [],
    warnings: [],
    sources: ['openai-vision'],
    model: 'test-online',
    verifiedCrop: 'eggplant',
  );

  @override
  String get baseUrl => 'http://offline.test';

  @override
  Future<AiBackendChatResponse> sendChatMessage({
    required String userMessage,
    String? cropId,
    DiagnosisModel? diagnosis,
    List<int>? imageBytes,
    List<List<int>> imageBytesList = const [],
    String? imageMimeType,
    List<Map<String, String>> conversationHistory = const [],
    String? locale,
    String? hintCropType,
    bool imagesFromPreviousTurns = false,
  }) async {
    sendCallCount++;
    lastCropId = cropId;
    lastHintCropType = hintCropType;
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseHelper database;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  });

  setUp(() async {
    database = DatabaseHelper.instance;
    await database.deleteDatabaseFile();
  });

  tearDown(() => database.deleteDatabaseFile());

  test('offline fallback is deterministic and bypasses the backend', () async {
    final supabase = _FakeSupabaseService();
    final backend = _TrackingAiBackendService(supabase: supabase);
    final provider = ChatProvider(
      supabase: supabase,
      db: database,
      aiBackend: backend,
      connectivity: _OfflineConnectivityService(),
      sync: _NoopSyncService(supabaseService: supabase, dbHelper: database),
    );
    addTearDown(provider.dispose);

    await provider.sendMessage(userId: 'offline-user', content: 'Hello');
    await provider.sendMessage(userId: 'offline-user', content: 'Hello');

    final assistantMessages = provider.currentMessages
        .where((message) => message.role == MessageRole.assistant)
        .toList();

    expect(backend.sendCallCount, 0);
    expect(provider.currentSession?.isOfflineSession, isTrue);
    expect(assistantMessages, hasLength(2));
    expect(assistantMessages[0].content, assistantMessages[1].content);
    expect(
      assistantMessages[0].content,
      contains('Hi. I\'m CropCare AI'),
    );
    expect(assistantMessages[0].metadata?['model'], 'local-fallback');
    expect(assistantMessages[1].metadata?['model'], 'local-fallback');
    for (final message in assistantMessages) {
      expect(message.metadata?['recommended_actions'], isEmpty);
      expect(message.metadata?['show_treatment_card'], isFalse);
      expect(message.metadata?['in_app_crop_scope'], isFalse);
      expect(message.metadata?['disease_name'], isEmpty);
      expect(message.metadata?['crop_type'], isEmpty);
    }
    final queuedTables = (await database.getPendingSyncItems())
        .map((item) => item['table_name'])
        .toSet();
    expect(
      queuedTables,
      containsAll([
        AppConstants.chatSessionsTable,
        AppConstants.chatMessagesTable,
      ]),
    );
  });

  test('accepted offline chat image creates treatment and add-crop cards',
      () async {
    final supabase = _FakeSupabaseService();
    final backend = _TrackingAiBackendService(supabase: supabase);
    final provider = ChatProvider(
      supabase: supabase,
      db: database,
      aiBackend: backend,
      connectivity: _OfflineConnectivityService(),
      sync: _NoopSyncService(supabaseService: supabase, dbHelper: database),
      localClassifier: _FakeLocalClassifierService(),
    );
    addTearDown(provider.dispose);

    await provider.sendMessage(
      userId: 'offline-user',
      content: 'Please analyze this crop photo.',
      attachedImageBytes: const [1, 2, 3],
    );

    expect(provider.currentMessages, hasLength(3));
    expect(provider.currentMessages.first.imageBytes, const [1, 2, 3]);
    final assistantMessage = provider.currentMessages.firstWhere(
      (message) => message.role == MessageRole.assistant,
    );
    expect(
      assistantMessage.content,
      contains('Eggplant Healthy'),
    );
    expect(assistantMessage.content, contains('91% confidence'));
    expect(assistantMessage.metadata?['crop_type'], 'eggplant');
    expect(assistantMessage.metadata?['show_treatment_card'], true);
    expect(assistantMessage.metadata?['recommended_actions'], isNotEmpty);
    expect(
        provider.currentMessages.last.metadata?['type'], 'add_crop_suggestion');
    expect(
        provider.currentMessages.last.metadata?['diagnosis_mode'], 'offline');
  });

  test(
      'high-confidence offline scan handoff keeps diagnosis and treatment card',
      () async {
    final supabase = _FakeSupabaseService();
    final backend = _TrackingAiBackendService(supabase: supabase);
    final provider = ChatProvider(
      supabase: supabase,
      db: database,
      aiBackend: backend,
      connectivity: _OfflineConnectivityService(),
      sync: _NoopSyncService(supabaseService: supabase, dbHelper: database),
    );
    addTearDown(provider.dispose);
    final now = DateTime.now();
    final diagnosis = DiagnosisModel(
      id: 'diagnosis-1',
      cropId: '',
      userId: 'offline-user',
      diagnosisMode: DiagnosisMode.offline,
      labelKey: 'eggplant_leaf_spot',
      diseaseName: 'Eggplant Leaf Spot',
      confidenceScore: 0.90,
      severity: Severity.moderate,
      summary: 'Provisional leaf-spot diagnosis.',
      modelName: 'test-tflite',
      modelVersion: '1',
      diagnosedAt: now,
      createdAt: now,
      updatedAt: now,
    );

    await provider.sendMessage(
      userId: 'offline-user',
      content: 'Please verify this scan.',
      attachedDiagnosis: diagnosis,
      attachedImageBytes: const [1, 2, 3],
      hintCropType: 'eggplant',
    );

    final assistantMessage = provider.currentMessages.firstWhere(
      (message) => message.role == MessageRole.assistant,
    );
    expect(assistantMessage.content, contains('Eggplant Leaf Spot'));
    expect(assistantMessage.content, isNot(contains('cannot reach')));
    expect(assistantMessage.metadata?['show_treatment_card'], true);
    expect(assistantMessage.metadata?['recommended_actions'], isNotEmpty);
    expect(
        provider.currentMessages.last.metadata?['type'], 'add_crop_suggestion');
    expect(
        provider.currentMessages.last.metadata?['diagnosis_mode'], 'offline');
  });

  test('uncertain offline image does not create treatment cards', () async {
    final supabase = _FakeSupabaseService();
    final provider = ChatProvider(
      supabase: supabase,
      db: database,
      aiBackend: _TrackingAiBackendService(supabase: supabase),
      connectivity: _OfflineConnectivityService(),
      sync: _NoopSyncService(supabaseService: supabase, dbHelper: database),
      localClassifier: _UncertainLocalClassifierService(),
    );
    addTearDown(provider.dispose);

    await provider.sendMessage(
      userId: 'offline-user',
      content: 'Please analyze this crop photo.',
      attachedImageBytes: const [1, 2, 3],
    );

    expect(provider.currentMessages, hasLength(2));
    final assistantMessage = provider.currentMessages.last;
    expect(assistantMessage.content, contains('not confident enough'));
    expect(assistantMessage.metadata?['show_treatment_card'], false);
    expect(assistantMessage.metadata?['recommended_actions'], isEmpty);
  });

  test('fresh online photo does not inherit a stale crop context', () async {
    final supabase = _FakeSupabaseService();
    final backend = _TrackingAiBackendService(supabase: supabase);
    final provider = ChatProvider(
      supabase: supabase,
      db: database,
      aiBackend: backend,
      connectivity: _OnlineConnectivityService(),
      sync: _NoopSyncService(supabaseService: supabase, dbHelper: database),
    );
    addTearDown(provider.dispose);

    await provider.startNewSession('online-user', cropId: 'tomato-crop-id');
    await provider.sendMessage(
      userId: 'online-user',
      content: 'Please analyze this crop photo.',
      attachedImageBytes: const [1, 2, 3],
      hintCropType: 'tomato',
    );

    expect(backend.sendCallCount, 1);
    expect(backend.lastCropId, isNull);
    expect(backend.lastHintCropType, isNull);
    expect(provider.currentMessages.last.metadata?['crop_type'], 'eggplant');
  });

  test('online photo diagnosis can show add-crop when backend UI flag is false',
      () async {
    final supabase = _FakeSupabaseService();
    final backend = _TrackingAiBackendService(supabase: supabase)
      ..response = const AiBackendChatResponse(
        answer:
            'Treatment: Remove affected leaves and inspect the plant daily.',
        recommendedActions: [],
        warnings: [],
        sources: ['openai-vision'],
        model: 'test-online',
        inAppCropScope: true,
        showTreatmentUi: false,
        verifiedCrop: 'eggplant',
        verifiedDisease: 'Eggplant Leaf Spot',
      );
    final provider = ChatProvider(
      supabase: supabase,
      db: database,
      aiBackend: backend,
      connectivity: _OnlineConnectivityService(),
      sync: _NoopSyncService(supabaseService: supabase, dbHelper: database),
    );
    addTearDown(provider.dispose);

    await provider.sendMessage(
      userId: 'online-user',
      content: 'Diagnose this eggplant and tell me how to treat it.',
      attachedImageBytes: const [1, 2, 3],
      hintCropType: 'eggplant',
    );

    final assistant = provider.currentMessages.firstWhere(
      (message) => message.role == MessageRole.assistant,
    );
    expect(assistant.metadata?['show_treatment_card'], isTrue);
    expect(assistant.metadata?['recommended_actions'], isNotEmpty);
    expect(
      provider.currentMessages.last.metadata?['type'],
      'add_crop_suggestion',
    );
  });

  test('uncertain AI diagnosis requests more evidence before crop handoff',
      () async {
    final supabase = _FakeSupabaseService();
    final backend = _TrackingAiBackendService(supabase: supabase)
      ..response = const AiBackendChatResponse(
        answer: 'What it is: Squash pest damage. '
            'Treatment: Check under leaves. '
            'The exact pest cannot be confirmed from this photo alone. '
            'A clear close-up of both sides of the leaf would improve identification.',
        recommendedActions: ['Check under leaves.'],
        warnings: [],
        sources: ['openai-vision'],
        model: 'test-online',
        inAppCropScope: true,
        showTreatmentUi: true,
        verifiedCrop: 'squash',
        verifiedDisease: 'Squash pest damage',
      );
    final provider = ChatProvider(
      supabase: supabase,
      db: database,
      aiBackend: backend,
      connectivity: _OnlineConnectivityService(),
      sync: _NoopSyncService(supabaseService: supabase, dbHelper: database),
    );
    addTearDown(provider.dispose);

    await provider.sendMessage(
      userId: 'online-user',
      content: 'Please diagnose this squash leaf.',
      attachedImageBytes: const [1, 2, 3],
      hintCropType: 'squash',
    );

    final assistant = provider.currentMessages.firstWhere(
      (message) => message.role == MessageRole.assistant,
    );
    expect(assistant.metadata?['show_treatment_card'], isFalse);
    expect(assistant.metadata?['recommended_actions'], isEmpty);
    expect(
      provider.currentMessages.any(
        (message) =>
            message.role == MessageRole.system &&
            message.metadata?['type'] == 'add_crop_suggestion',
      ),
      isFalse,
    );
  });

  test('online photo review replaces the TFLite crop and disease', () async {
    final supabase = _FakeSupabaseService();
    final backend = _TrackingAiBackendService(supabase: supabase)
      ..response = const AiBackendChatResponse(
        answer:
            'What it is: Severe Eggplant Leaf Spot. Treatment: Remove affected leaves and improve airflow.',
        recommendedActions: [
          'Remove affected leaves.',
          'Improve airflow around the eggplant.',
        ],
        warnings: [],
        sources: ['openai-vision'],
        model: 'test-online',
        inAppCropScope: true,
        showTreatmentUi: true,
        verifiedCrop: 'eggplant',
        verifiedDisease: 'Eggplant Leaf Spot',
      );
    final provider = ChatProvider(
      supabase: supabase,
      db: database,
      aiBackend: backend,
      connectivity: _OnlineConnectivityService(),
      sync: _NoopSyncService(supabaseService: supabase, dbHelper: database),
    );
    addTearDown(provider.dispose);
    final now = DateTime.now();
    final tfliteDiagnosis = DiagnosisModel(
      id: 'tflite-diagnosis',
      cropId: '',
      userId: 'online-user',
      diagnosisMode: DiagnosisMode.offline,
      labelKey: 'tomato_leaf_mold',
      diseaseName: 'Tomato Leaf Mold',
      confidenceScore: 0.91,
      severity: Severity.moderate,
      summary: 'Preliminary local scanner result.',
      modelName: 'test-tflite',
      modelVersion: '1',
      diagnosedAt: now,
      createdAt: now,
      updatedAt: now,
    );

    await provider.sendMessage(
      userId: 'online-user',
      content:
          'The TFLite scanner produced a preliminary result. Verify it against this photo.',
      attachedDiagnosis: tfliteDiagnosis,
      attachedImageBytes: const [1, 2, 3],
      hintCropType: 'tomato',
    );

    final assistant = provider.currentMessages.firstWhere(
      (message) => message.role == MessageRole.assistant,
    );
    final suggestion = provider.currentMessages.firstWhere(
      (message) =>
          message.role == MessageRole.system &&
          message.metadata?['type'] == 'add_crop_suggestion',
    );
    expect(assistant.metadata?['crop_type'], 'eggplant');
    expect(assistant.metadata?['disease_name'], 'Eggplant Leaf Spot');
    expect(assistant.metadata?['severity'], Severity.severe.value);
    expect(assistant.metadata?['recommended_actions'], [
      'Remove affected leaves.',
      'Improve airflow around the eggplant.',
    ]);
    expect(suggestion.metadata?['crop_type'], 'eggplant');
    expect(suggestion.metadata?['disease_name'], 'Eggplant Leaf Spot');
    expect(suggestion.metadata?['severity'], Severity.severe.value);
    expect(suggestion.metadata?['diagnosis_mode'], DiagnosisMode.online.value);
    expect(suggestion.metadata?['recommended_actions'], [
      'Remove affected leaves.',
      'Improve airflow around the eggplant.',
    ]);
    expect(suggestion.metadata?['diagnosis_mode'], DiagnosisMode.online.value);
    expect(
      suggestion.metadata?['recommended_actions'],
      backend.response.recommendedActions,
    );
  });
}
