import 'package:cropcare_ai/core/constants/app_constants.dart';
import 'package:cropcare_ai/core/constants/app_enums.dart';
import 'package:cropcare_ai/data/local/database_helper.dart';
import 'package:cropcare_ai/data/models/diagnosis_model.dart';
import 'package:cropcare_ai/data/remote/ai_backend_service.dart';
import 'package:cropcare_ai/data/remote/supabase_service.dart';
import 'package:cropcare_ai/features/chat/providers/chat_provider.dart';
import 'package:cropcare_ai/services/connectivity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _OfflineConnectivityService extends ConnectivityService {
  @override
  Future<bool> get isConnected async => false;
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
}

class _TrackingAiBackendService extends AiBackendService {
  _TrackingAiBackendService({required super.supabase});

  int sendCallCount = 0;

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
  }) async {
    sendCallCount++;
    throw StateError('Backend must not be called while offline');
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
      contains('You are using the offline model'),
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
  });

  test('single scan image reaches offline fallback without aborting', () async {
    final supabase = _FakeSupabaseService();
    final backend = _TrackingAiBackendService(supabase: supabase);
    final provider = ChatProvider(
      supabase: supabase,
      db: database,
      aiBackend: backend,
      connectivity: _OfflineConnectivityService(),
    );
    addTearDown(provider.dispose);

    await provider.sendMessage(
      userId: 'offline-user',
      content: 'Please analyze this crop photo.',
      attachedImageBytes: const [1, 2, 3],
    );

    expect(provider.currentMessages, hasLength(2));
    expect(provider.currentMessages.first.imageBytes, const [1, 2, 3]);
    expect(
      provider.currentMessages.last.content,
      contains('cannot safely identify a crop or disease'),
    );
  });
}
