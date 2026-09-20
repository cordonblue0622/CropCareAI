import 'dart:async';
import 'dart:convert';

import 'package:cropcare_ai/core/constants/app_constants.dart';
import 'package:cropcare_ai/core/constants/app_enums.dart';
import 'package:cropcare_ai/data/local/database_helper.dart';
import 'package:cropcare_ai/data/models/chat_message_model.dart';
import 'package:cropcare_ai/data/models/chat_session_model.dart';
import 'package:cropcare_ai/data/models/diagnosis_model.dart';
import 'package:cropcare_ai/data/models/user_model.dart';
import 'package:cropcare_ai/data/remote/ai_backend_service.dart';
import 'package:cropcare_ai/data/remote/supabase_service.dart';
import 'package:cropcare_ai/data/repositories/auth_repository.dart';
import 'package:cropcare_ai/features/auth/providers/auth_provider.dart';
import 'package:cropcare_ai/features/chat/providers/chat_provider.dart';
import 'package:cropcare_ai/features/chat/screens/chat_screen.dart';
import 'package:cropcare_ai/services/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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

class _RecordingChatProvider extends ChatProvider {
  _RecordingChatProvider({
    required super.supabase,
    required super.db,
    required super.aiBackend,
    required super.connectivity,
  });

  final List<ChatMessageModel> _messages = [];
  final List<ChatSessionModel> _availableSessions = [];
  ChatSessionModel? _session;
  int sendCallCount = 0;

  @override
  List<ChatMessageModel> get currentMessages => _messages;

  @override
  List<ChatSessionModel> get sessions => _availableSessions;

  @override
  ChatSessionModel? get currentSession => _session;

  @override
  bool get isLoading => false;

  @override
  bool get isTyping => false;

  void seedConversation(
    ChatSessionModel session,
    List<ChatMessageModel> messages,
  ) {
    _availableSessions.add(session);
    _messages
      ..clear()
      ..addAll(messages);
  }

  @override
  Future<void> fetchSessions(String userId) async {}

  @override
  Future<void> loadSession(ChatSessionModel session) async {
    _session = session;
    notifyListeners();
  }

  @override
  Future<void> startNewSession(String userId, {String? cropId}) async {
    final now = DateTime.now();
    _session = ChatSessionModel(
      id: 'scan-session',
      userId: userId,
      cropId: cropId,
      createdAt: now,
      updatedAt: now,
    );
    _messages.clear();
    notifyListeners();
  }

  @override
  Future<void> sendMessage({
    required String userId,
    required String content,
    bool hideMessageTextInUi = false,
    DiagnosisModel? attachedDiagnosis,
    List<int>? attachedImageBytes,
    List<List<int>> attachedImageBytesList = const [],
    String? attachedAudioPath,
    String? attachedVideoPath,
    String? attachedImageMimeType,
    bool isVideoFrame = false,
    String? hintCropType,
  }) async {
    sendCallCount++;
    final now = DateTime.now();
    final imageBytes = attachedImageBytes == null
        ? null
        : Uint8List.fromList(attachedImageBytes);
    _messages
      ..add(ChatMessageModel(
        id: 'user-message',
        sessionId: _session!.id,
        userId: userId,
        role: MessageRole.user,
        content: content,
        createdAt: now,
        imageBytes: imageBytes,
        imageBytesList: imageBytes == null ? null : [imageBytes],
      ))
      ..add(ChatMessageModel(
        id: 'assistant-message',
        sessionId: _session!.id,
        userId: userId,
        role: MessageRole.assistant,
        content: 'Recorded response',
        createdAt: now,
      ));
    notifyListeners();
  }
}

class _DelayedAuthRepository extends AuthRepository {
  _DelayedAuthRepository({
    required super.supabaseService,
    required super.dbHelper,
  });

  final Completer<UserModel?> _restoration = Completer<UserModel?>();
  UserModel? _user;

  @override
  bool get isSignedIn => true;

  @override
  UserModel? get currentUser => _user;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Future<UserModel?> loadCurrentUser() => _restoration.future;

  void completeRestoration(UserModel user) {
    _user = user;
    _restoration.complete(user);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const connectivityStatusChannel =
      MethodChannel('dev.fluttercommunity.plus/connectivity_status');

  late DatabaseHelper database;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityStatusChannel, (_) async => null);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityStatusChannel, null);
  });

  setUp(() async {
    database = DatabaseHelper.instance;
    await database.deleteDatabaseFile();
  });

  tearDown(() => database.deleteDatabaseFile());

  testWidgets('scan waits for auth restoration and sends its image once',
      (tester) async {
    final scanBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final supabase = _FakeSupabaseService();
    final authRepository = _DelayedAuthRepository(
      supabaseService: supabase,
      dbHelper: database,
    );
    final authProvider = AuthProvider(authRepository: authRepository);
    final chatProvider = _RecordingChatProvider(
      supabase: supabase,
      db: database,
      aiBackend: AiBackendService(supabase: supabase),
      connectivity: _OfflineConnectivityService(),
    );
    addTearDown(authProvider.dispose);
    addTearDown(chatProvider.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
        ],
        child: MaterialApp(
          home: ChatScreen(
            startFreshSession: true,
            initialImageBytes: scanBytes,
            hintCropType: 'tomato',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Preparing your crop analysis...'), findsOneWidget);
    expect(find.text('Try asking:'), findsNothing);
    expect(chatProvider.currentMessages, isEmpty);

    authRepository.completeRestoration(
      const UserModel(id: 'scan-user', email: 'scan@example.com'),
    );
    await tester.pump();
    await tester.pump();

    expect(chatProvider.currentMessages, hasLength(2));
    expect(chatProvider.currentMessages.first.imageBytes, scanBytes);
    expect(
      chatProvider.currentMessages
          .where((message) => message.imageBytes != null),
      hasLength(1),
    );
    expect(find.text('Try asking:'), findsNothing);
  });

  testWidgets('saved diagnosis opens its linked conversation without resending',
      (tester) async {
    final now = DateTime.now();
    final session = ChatSessionModel(
      id: 'saved-session',
      userId: 'saved-user',
      cropId: 'crop-1',
      createdAt: now.subtract(const Duration(days: 2)),
      updatedAt: now.subtract(const Duration(days: 2)),
    );
    final savedMessage = ChatMessageModel(
      id: 'saved-message',
      sessionId: session.id,
      userId: 'saved-user',
      role: MessageRole.assistant,
      content: 'Past eggplant diagnosis conversation',
      createdAt: session.createdAt,
    );
    final diagnosis = DiagnosisModel(
      id: 'diagnosis-1',
      cropId: 'crop-1',
      userId: 'saved-user',
      chatSessionId: session.id,
      diagnosisMode: DiagnosisMode.online,
      diseaseName: 'Eggplant Leaf Spot',
      confidenceScore: 0.9,
      diagnosedAt: session.createdAt,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
    );
    final supabase = _FakeSupabaseService();
    final authRepository = _DelayedAuthRepository(
      supabaseService: supabase,
      dbHelper: database,
    );
    final authProvider = AuthProvider(authRepository: authRepository);
    final chatProvider = _RecordingChatProvider(
      supabase: supabase,
      db: database,
      aiBackend: AiBackendService(supabase: supabase),
      connectivity: _OfflineConnectivityService(),
    )..seedConversation(session, [savedMessage]);
    addTearDown(authProvider.dispose);
    addTearDown(chatProvider.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
        ],
        child: MaterialApp(
          home: ChatScreen(
            cropId: 'crop-1',
            initialDiagnosis: diagnosis,
            startFreshSession: false,
          ),
        ),
      ),
    );
    await tester.pump();

    authRepository.completeRestoration(
      const UserModel(id: 'saved-user', email: 'saved@example.com'),
    );
    await tester.pump();
    await tester.pump();

    expect(chatProvider.currentSession?.id, 'saved-session');
    expect(chatProvider.sendCallCount, 0);
    expect(find.text('Past eggplant diagnosis conversation'), findsOneWidget);
  });
}
