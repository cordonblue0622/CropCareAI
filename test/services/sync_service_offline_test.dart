import 'dart:async';
import 'dart:convert';

import 'package:cropcare_ai/core/constants/app_constants.dart';
import 'package:cropcare_ai/core/constants/app_enums.dart';
import 'package:cropcare_ai/data/local/database_helper.dart';
import 'package:cropcare_ai/data/models/chat_message_model.dart';
import 'package:cropcare_ai/data/models/chat_session_model.dart';
import 'package:cropcare_ai/data/models/crop_model.dart';
import 'package:cropcare_ai/data/models/diagnosis_model.dart';
import 'package:cropcare_ai/data/models/progress_update_model.dart';
import 'package:cropcare_ai/data/models/treatment_model.dart';
import 'package:cropcare_ai/data/models/treatment_task_model.dart';
import 'package:cropcare_ai/data/remote/ai_backend_service.dart';
import 'package:cropcare_ai/data/remote/supabase_service.dart';
import 'package:cropcare_ai/services/sync_service.dart';
import 'package:cropcare_ai/core/utils/image_reference.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeSupabaseService extends SupabaseService {
  final remoteRows = <String, List<Map<String, dynamic>>>{};
  final failUpsertsOnce = <String>{};
  int upsertCalls = 0;
  int deleteCalls = 0;
  final upsertedTables = <String>[];
  String? ownerId = 'offline-user';
  bool signedIn = false;

  @override
  String? get authenticatedUserId => ownerId;

  @override
  bool get isSignedIn => signedIn;

  List<Map<String, dynamic>> _rows(String table) =>
      remoteRows[table] ?? const [];

  int remoteCount(String table) => _rows(table).length;

  @override
  Future<void> upsertRecord({
    required String table,
    required Map<String, dynamic> data,
  }) async {
    upsertCalls++;
    upsertedTables.add(table);
    if (failUpsertsOnce.remove(table)) {
      throw StateError('simulated $table synchronization failure');
    }
    final rows = remoteRows.putIfAbsent(table, () => []);
    rows.removeWhere((row) => row['id'] == data['id']);
    rows.add(Map<String, dynamic>.from(data));
  }

  @override
  Future<void> deleteRecord({
    required String table,
    required String id,
  }) async {
    deleteCalls++;
    remoteRows[table]?.removeWhere((row) => row['id'] == id);
  }

  @override
  Future<String?> uploadChatImage({
    required String userId,
    required String messageId,
    required List<int> bytes,
  }) async =>
      'https://storage.example/$userId/$messageId.jpg';

  @override
  Future<Map<String, dynamic>?> getProfile(String userId) async => null;

  @override
  Future<List<Map<String, dynamic>>> getCropsIncludingDeleted(
    String userId,
  ) async =>
      _rows(AppConstants.cropsTable);

  @override
  Future<List<Map<String, dynamic>>> getDiagnosesIncludingDeleted(
    String userId,
  ) async =>
      _rows(AppConstants.diagnosesTable);

  @override
  Future<List<Map<String, dynamic>>> getTreatmentsIncludingDeleted(
    String userId,
  ) async =>
      _rows(AppConstants.treatmentsTable);

  @override
  Future<List<Map<String, dynamic>>> getAllTreatmentTasksByUser(
    String userId,
  ) async =>
      _rows(AppConstants.treatmentTasksTable);

  @override
  Future<List<Map<String, dynamic>>> getNotifications(String userId) async =>
      _rows(AppConstants.notificationsTable);

  @override
  Future<List<Map<String, dynamic>>> getChatSessions(String userId) async =>
      _rows(AppConstants.chatSessionsTable);

  @override
  Future<List<Map<String, dynamic>>> getProgressUpdates(String cropId) async =>
      _rows(AppConstants.progressUpdatesTable)
          .where((row) => row['crop_id'] == cropId)
          .toList();

  @override
  Future<List<Map<String, dynamic>>> getChatMessages(String sessionId) async =>
      _rows(AppConstants.chatMessagesTable)
          .where((row) => row['session_id'] == sessionId)
          .toList();
}

class _FakeAiBackendService extends AiBackendService {
  int assessmentCalls = 0;

  _FakeAiBackendService({required super.supabase});

  @override
  Future<AiBackendProgressResponse> assessCropHealth({
    required String cropType,
    required String diseaseName,
    int daysSinceTreatment = 0,
    List<int>? imageBytes,
    String? imageMimeType,
    String? imageDataUrl,
    String? previousImageReference,
    String? previousAssessment,
    String? previousProgressStatus,
    String? previousUpdateDate,
    List<String> completedTasks = const [],
    String? note,
    double? currentHealthScore,
  }) async {
    assessmentCalls++;
    return const AiBackendProgressResponse(
      accepted: true,
      rejectionReason: null,
      healthScore: 82,
      progressStatus: 'improving',
      assessment: 'New leaves show improvement.',
      nextSteps: ['Continue daily inspection.'],
    );
  }
}

Map<String, List<Map<String, dynamic>>> _fixtureRows(DateTime now) {
  final crop = CropModel(
    id: 'crop-offline',
    userId: 'offline-user',
    cropType: CropType.eggplant,
    cropName: 'Offline eggplant',
    createdAt: now,
    updatedAt: now,
  );
  final session = ChatSessionModel(
    id: 'session-offline',
    userId: crop.userId,
    cropId: crop.id,
    isOfflineSession: true,
    createdAt: now,
    updatedAt: now,
  );
  final diagnosis = DiagnosisModel(
    id: 'diagnosis-offline',
    cropId: crop.id,
    userId: crop.userId,
    chatSessionId: session.id,
    diagnosisMode: DiagnosisMode.offline,
    labelKey: 'eggplant_leaf_spot',
    diseaseName: 'Eggplant Leaf Spot',
    confidenceScore: 0.91,
    summary: 'Offline diagnosis summary',
    modelName: 'test-tflite',
    modelVersion: '1',
    diagnosedAt: now,
    createdAt: now,
    updatedAt: now,
  );
  final treatment = TreatmentModel(
    id: 'treatment-offline',
    cropId: crop.id,
    diagnosisId: diagnosis.id,
    userId: crop.userId,
    diseaseName: diagnosis.diseaseName,
    treatmentTitle: 'Offline treatment',
    treatmentSteps: const ['Inspect leaves daily for new spots.'],
    startedAt: now,
    createdAt: now,
    updatedAt: now,
  );
  final task = TreatmentTaskModel(
    id: 'task-offline',
    treatmentId: treatment.id,
    cropId: crop.id,
    userId: crop.userId,
    title: 'Inspect leaves daily for new spots.',
    dueAt: now,
    taskOrder: 1,
    createdAt: now,
    updatedAt: now,
  );
  final message = ChatMessageModel(
    id: 'message-offline',
    sessionId: session.id,
    userId: crop.userId,
    role: MessageRole.assistant,
    content: 'Offline diagnosis conversation',
    createdAt: now,
  );
  return {
    AppConstants.cropsTable: [crop.toMap()],
    AppConstants.chatSessionsTable: [session.toMap()],
    AppConstants.diagnosesTable: [diagnosis.toMap()],
    AppConstants.treatmentsTable: [treatment.toMap()],
    AppConstants.treatmentTasksTable: [task.toMap()],
    AppConstants.chatMessagesTable: [message.toMap()],
  };
}

Map<String, dynamic> _remoteRow(String table, Map<String, dynamic> local) {
  final remote = Map<String, dynamic>.from(local);
  if (table == AppConstants.treatmentsTable) {
    remote['treatment_steps'] = jsonDecode(remote['treatment_steps'] as String);
    remote['reassessment_required'] = remote['reassessment_required'] == true ||
        remote['reassessment_required'] == 1;
  }
  if (remote.containsKey('is_deleted')) {
    remote['is_deleted'] =
        remote['is_deleted'] == true || remote['is_deleted'] == 1;
  }
  if (table == AppConstants.chatSessionsTable) {
    remote['is_offline_session'] = remote['is_offline_session'] == true ||
        remote['is_offline_session'] == 1;
  }
  return remote;
}

List<LocalSyncUpsert> _writes(
  Map<String, List<Map<String, dynamic>>> rows,
) {
  return [
    for (final entry in rows.entries)
      for (final row in entry.value)
        LocalSyncUpsert(
          tableName: entry.key,
          recordId: row['id'] as String,
          localData: row,
          remoteData: _remoteRow(entry.key, row),
        ),
  ];
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

  test('failed related sync preserves local data and retries idempotently',
      () async {
    final supabase = _FakeSupabaseService();
    final sync = SyncService(
      supabaseService: supabase,
      dbHelper: database,
    );
    final rows = _fixtureRows(DateTime.utc(2026, 10, 31, 9));
    await sync.persistQueuedUpserts(_writes(rows));
    supabase.failUpsertsOnce.add(AppConstants.treatmentsTable);

    await sync.pushPendingChanges();

    expect(supabase.remoteCount(AppConstants.cropsTable), 1);
    expect(supabase.remoteCount(AppConstants.diagnosesTable), 1);
    expect(supabase.remoteCount(AppConstants.treatmentsTable), 0);
    expect(supabase.remoteCount(AppConstants.treatmentTasksTable), 0);
    expect(
      await database.queryTreatmentsForCrop('crop-offline'),
      hasLength(1),
    );
    expect(await database.queryAllTasksForCrop('crop-offline'), hasLength(1));
    final failedItems = await database.getPendingSyncItems();
    expect(
      failedItems.map((item) => item['table_name']).toSet(),
      containsAll([
        AppConstants.treatmentsTable,
        AppConstants.treatmentTasksTable,
      ]),
    );
    final failedTreatment = failedItems.singleWhere(
      (item) => item['table_name'] == AppConstants.treatmentsTable,
    );
    expect(failedTreatment['attempts'], 1);
    expect(failedTreatment['last_error'], contains('simulated'));

    await sync.pushPendingChanges();

    expect(await database.getPendingSyncItems(), isEmpty);
    for (final table in rows.keys) {
      expect(supabase.remoteCount(table), 1, reason: '$table must sync once');
    }
    final remoteTreatment =
        supabase.remoteRows[AppConstants.treatmentsTable]!.single;
    final remoteTask =
        supabase.remoteRows[AppConstants.treatmentTasksTable]!.single;
    expect(remoteTreatment['crop_id'], 'crop-offline');
    expect(remoteTreatment['diagnosis_id'], 'diagnosis-offline');
    expect(remoteTask['treatment_id'], 'treatment-offline');
    expect(remoteTask['crop_id'], 'crop-offline');

    final callsAfterSuccessfulSync = supabase.upsertCalls;
    await sync.pushPendingChanges();
    expect(supabase.upsertCalls, callsAfterSuccessfulSync);
    for (final table in rows.keys) {
      expect(
        supabase.remoteCount(table),
        1,
        reason: 'Repeated sync must not duplicate $table',
      );
    }

    await database.closeDatabase();
    expect(
      await database.queryDiagnosesForCrop('crop-offline'),
      hasLength(1),
    );
    expect(await database.queryTreatmentsForCrop('crop-offline'), hasLength(1));
    expect(await database.queryAllTasksForCrop('crop-offline'), hasLength(1));
    expect(
        await database.queryChatSessionsByCrop('crop-offline'), hasLength(1));
    expect(await database.queryChatMessages('session-offline'), hasLength(1));
  });

  test('progress images stay local and analysis queues after submission sync',
      () async {
    final supabase = _FakeSupabaseService();
    final aiBackend = _FakeAiBackendService(supabase: supabase);
    final sync = SyncService(
      supabaseService: supabase,
      dbHelper: database,
      aiBackend: aiBackend,
    );
    final now = DateTime.utc(2026, 10, 31, 11);
    final crop = CropModel(
      id: 'crop-progress',
      userId: 'offline-user',
      cropType: CropType.tomato,
      cropName: 'Tomato',
      createdAt: now,
      updatedAt: now,
    );
    final photo = buildInlineImageDataUrl([1, 2, 3, 4]);
    final progress = ProgressUpdateModel(
      id: 'progress-offline',
      cropId: crop.id,
      userId: crop.userId,
      note: 'Offline check-in; AI analysis pending.',
      imageUrl: photo,
      progressStatus: ProgressStatus.insufficientData,
      updateDate: now,
      aiAnalysisStatus: AiAnalysisStatus.pending,
      createdAt: now,
      updatedAt: now,
    );
    await sync.persistQueuedUpserts([
      LocalSyncUpsert(
        tableName: AppConstants.cropsTable,
        recordId: crop.id,
        localData: crop.toMap(),
        remoteData: _remoteRow(AppConstants.cropsTable, crop.toMap()),
      ),
      LocalSyncUpsert(
        tableName: AppConstants.progressUpdatesTable,
        recordId: progress.id,
        localData: progress.toMap(),
        remoteData: progress.toRemoteMap(),
      ),
    ]);

    await sync.reassessPendingPhotoCheckInsForTest(crop.userId);
    expect(aiBackend.assessmentCalls, 0,
        reason: 'AI analysis must wait for the submitted progress row to sync');
    await sync.pushPendingChanges();
    expect(
      supabase
          .remoteRows[AppConstants.progressUpdatesTable]!.single['image_url'],
      startsWith('https://storage.example/'),
    );
    expect(
      (await database.queryById(
          AppConstants.progressUpdatesTable, progress.id))?['image_url'],
      photo,
      reason: 'Sync must preserve the local photo for offline viewing',
    );

    await sync.reassessPendingPhotoCheckInsForTest(crop.userId);
    expect(aiBackend.assessmentCalls, 1);
    final locallyAssessed = ProgressUpdateModel.fromMap(
      (await database.queryById(
          AppConstants.progressUpdatesTable, progress.id))!,
    );
    expect(locallyAssessed.aiAnalysisStatus, AiAnalysisStatus.completed);
    expect(locallyAssessed.note, 'New leaves show improvement.');
    expect(locallyAssessed.imageUrl, photo);

    supabase.failUpsertsOnce.add(AppConstants.progressUpdatesTable);
    await sync.pushPendingChanges();
    expect(
      (await database.getPendingSyncItems()).any(
          (item) => item['table_name'] == AppConstants.progressUpdatesTable),
      isTrue,
    );
    expect(
      ProgressUpdateModel.fromMap(
        (await database.queryById(
            AppConstants.progressUpdatesTable, progress.id))!,
      ).aiAnalysisStatus,
      AiAnalysisStatus.completed,
      reason: 'A cloud failure must not discard local AI results',
    );

    await sync.pushPendingChanges();
    final remoteProgress =
        supabase.remoteRows[AppConstants.progressUpdatesTable]!.single;
    expect(remoteProgress['note'], 'New leaves show improvement.');
    expect(remoteProgress['progress_status'], ProgressStatus.improving.value);
    expect(remoteProgress.containsKey('ai_analysis_status'), isFalse,
        reason: 'Local AI bookkeeping must not require a cloud schema change');
    await sync.pullFromRemote(userId: crop.userId);
    expect(
      (await database.queryById(
          AppConstants.progressUpdatesTable, progress.id))?['image_url'],
      photo,
      reason: 'Pulling the uploaded URL back must not erase local photo bytes',
    );
    expect(await database.getPendingSyncItems(), isEmpty);
  });

  test('queued writes wait for the authenticated owner', () async {
    final supabase = _FakeSupabaseService()..ownerId = 'another-user';
    final sync = SyncService(
      supabaseService: supabase,
      dbHelper: database,
    );
    final rows = _fixtureRows(DateTime.utc(2026, 10, 31, 12));
    await sync.persistQueuedUpserts(_writes(rows));

    await sync.pushPendingChanges();
    expect(supabase.upsertCalls, 0);
    expect(await database.getPendingSyncItems(), hasLength(6));

    supabase.ownerId = 'offline-user';
    await sync.pushPendingChanges();
    expect(await database.getPendingSyncItems(), isEmpty);
    expect(supabase.remoteCount(AppConstants.cropsTable), 1);
  });

  test('delete operations require a verifiable matching owner', () async {
    final supabase = _FakeSupabaseService()..ownerId = 'another-user';
    final sync = SyncService(
      supabaseService: supabase,
      dbHelper: database,
    );
    await sync.queueDelete(
      tableName: AppConstants.cropsTable,
      recordId: 'crop-owned-by-offline-user',
      userId: 'offline-user',
    );
    await sync.queueDelete(
      tableName: AppConstants.cropsTable,
      recordId: 'crop-with-unknown-owner',
    );

    await sync.pushPendingChanges();
    expect(supabase.deleteCalls, 0);
    expect(await database.getPendingSyncItems(), hasLength(2));

    supabase.ownerId = 'offline-user';
    await sync.pushPendingChanges();
    expect(supabase.deleteCalls, 1);
    expect(await database.getPendingSyncItems(), hasLength(1));
  });

  test('remote image URLs do not replace the local diagnosis or chat photos',
      () async {
    final now = DateTime.utc(2026, 10, 31, 12, 30);
    final diagnosis = DiagnosisModel(
      id: 'diagnosis-with-photo',
      cropId: 'crop-offline',
      userId: 'offline-user',
      diagnosisMode: DiagnosisMode.offline,
      labelKey: 'tomato_early_blight',
      diseaseName: 'Tomato Early Blight',
      confidenceScore: 0.9,
      diagnosedAt: now,
      createdAt: now,
      updatedAt: now,
    ).toMap()
      ..['image_url'] = buildInlineImageDataUrl([1, 2, 3]);
    final remoteDiagnosis = Map<String, dynamic>.from(diagnosis)
      ..['image_url'] = 'https://storage.example/diagnosis.jpg';
    final mergedDiagnosis = SyncService.preserveLocalImageReferences(
      localRows: [diagnosis],
      mergedRows: [remoteDiagnosis],
    ).single;
    expect(mergedDiagnosis['image_url'], diagnosis['image_url']);

    final firstPhoto = buildInlineImageDataUrl([1, 2, 3]);
    final secondPhoto = buildInlineImageDataUrl([4, 5, 6]);
    final localMessage = ChatMessageModel(
      id: 'message-with-photos',
      sessionId: 'session-offline',
      userId: 'offline-user',
      role: MessageRole.user,
      content: 'These leaves need checking.',
      metadata: {
        'image_url': firstPhoto,
        'image_urls': [firstPhoto, secondPhoto],
      },
      createdAt: now,
    ).toMap();
    final remoteMessage = Map<String, dynamic>.from(localMessage)
      ..['metadata'] = jsonEncode({
        'image_url': 'https://storage.example/message-0.jpg',
        'image_urls': [
          'https://storage.example/message-0.jpg',
          'https://storage.example/message-1.jpg',
        ],
      });
    final mergedMessage = SyncService.preserveLocalChatImages(
      localRows: [localMessage],
      mergedRows: [remoteMessage],
    ).single;
    expect(
      ChatMessageModel.fromMap(mergedMessage).imageUrls,
      [firstPhoto, secondPhoto],
    );
  });

  test('offline diagnosis and conversation photos upload and remain offline',
      () async {
    final supabase = _FakeSupabaseService();
    final sync = SyncService(
      supabaseService: supabase,
      dbHelper: database,
    );
    final now = DateTime.utc(2026, 10, 31, 12, 45);
    final rows = _fixtureRows(now);
    final diagnosisPhoto = buildInlineImageDataUrl([1, 3, 5]);
    rows[AppConstants.diagnosesTable] = [
      Map<String, dynamic>.from(rows[AppConstants.diagnosesTable]!.single)
        ..['image_url'] = diagnosisPhoto,
    ];
    final firstPhoto = buildInlineImageDataUrl([2, 4, 6]);
    final secondPhoto = buildInlineImageDataUrl([7, 8, 9]);
    rows[AppConstants.chatMessagesTable]!.add(
      ChatMessageModel(
        id: 'offline-photo-message',
        sessionId: 'session-offline',
        userId: 'offline-user',
        role: MessageRole.user,
        content: 'Please check these leaves.',
        metadata: {
          'image_url': firstPhoto,
          'image_urls': [firstPhoto, secondPhoto],
        },
        createdAt: now,
      ).toMap(),
    );
    await sync.persistQueuedUpserts(_writes(rows));

    await sync.pushPendingChanges();
    final remoteDiagnosis =
        supabase.remoteRows[AppConstants.diagnosesTable]!.single;
    expect(
        remoteDiagnosis['image_url'], startsWith('https://storage.example/'));
    final remoteMessage = supabase.remoteRows[AppConstants.chatMessagesTable]!
        .singleWhere((row) => row['id'] == 'offline-photo-message');
    final rawRemoteMetadata = remoteMessage['metadata'];
    final remoteMetadata = rawRemoteMetadata is String
        ? jsonDecode(rawRemoteMetadata) as Map<String, dynamic>
        : Map<String, dynamic>.from(rawRemoteMetadata as Map);
    expect(remoteMetadata['image_urls'], hasLength(2));
    expect(
      (remoteMetadata['image_urls'] as List).every(
          (url) => url.toString().startsWith('https://storage.example/')),
      isTrue,
    );

    await sync.pullFromRemote(userId: 'offline-user');
    final localDiagnosis = DiagnosisModel.fromMap(
      (await database.queryDiagnosesForCrop('crop-offline')).single,
    );
    expect(localDiagnosis.imageUrl, diagnosisPhoto);
    final localChatMessages =
        await database.queryChatMessages('session-offline');
    final localPhotoMessage = ChatMessageModel.fromMap(
      localChatMessages
          .singleWhere((row) => row['id'] == 'offline-photo-message'),
    );
    expect(localPhotoMessage.imageUrls, [firstPhoto, secondPhoto]);
    expect(await database.getPendingSyncItems(), isEmpty);
  });

  test('pulled cloud crop data remains locally available after restart',
      () async {
    final supabase = _FakeSupabaseService();
    final rows = _fixtureRows(DateTime.utc(2026, 10, 31, 10));
    supabase.remoteRows.addAll(
      rows.map(
        (table, records) => MapEntry(
          table,
          records.map((row) => _remoteRow(table, row)).toList(),
        ),
      ),
    );
    final sync = SyncService(
      supabaseService: supabase,
      dbHelper: database,
    );

    await sync.pullFromRemote(userId: 'offline-user');
    await database.closeDatabase();
    supabase.remoteRows.clear();

    expect(
      (await database.queryById(
          AppConstants.cropsTable, 'crop-offline'))?['crop_name'],
      'Offline eggplant',
    );
    final diagnosis = DiagnosisModel.fromMap(
      (await database.queryDiagnosesForCrop('crop-offline')).single,
    );
    expect(diagnosis.confidenceScore, 0.91);
    expect(diagnosis.summary, 'Offline diagnosis summary');
    final treatment = TreatmentModel.fromMap(
      (await database.queryTreatmentsForCrop('crop-offline')).single,
    );
    expect(treatment.diagnosisId, diagnosis.id);
    expect(treatment.treatmentSteps, ['Inspect leaves daily for new spots.']);
    final task = TreatmentTaskModel.fromMap(
      (await database.queryAllTasksForCrop('crop-offline')).single,
    );
    expect(task.treatmentId, treatment.id);
    expect(task.cropId, diagnosis.cropId);
    expect(
        await database.queryChatSessionsByCrop('crop-offline'), hasLength(1));
    final messages = await database.queryChatMessages('session-offline');
    expect(messages, hasLength(1));
    expect(messages.single['content'], 'Offline diagnosis conversation');
    expect(await database.getPendingSyncItems(), isEmpty);
  });

  test('newer local edits replace stale queued payloads without duplicates',
      () async {
    final supabase = _FakeSupabaseService();
    final sync = SyncService(
      supabaseService: supabase,
      dbHelper: database,
    );
    final rows = _fixtureRows(DateTime.utc(2026, 10, 31, 9));
    await sync.persistQueuedUpserts(_writes(rows));
    final original = TreatmentTaskModel.fromMap(
        rows[AppConstants.treatmentTasksTable]!.single);
    final completed = original.copyWith(
      status: TaskStatus.completed,
      completedAt: DateTime.utc(2026, 11, 1, 8),
      updatedAt: DateTime.utc(2026, 11, 1, 8),
    );
    await sync.persistQueuedUpserts([
      LocalSyncUpsert(
        tableName: AppConstants.treatmentTasksTable,
        recordId: completed.id,
        localData: completed.toMap(),
        remoteData: _remoteRow(
          AppConstants.treatmentTasksTable,
          completed.toMap(),
        ),
      ),
    ]);

    final queuedTasks = (await database.getPendingSyncItems())
        .where((item) =>
            item['table_name'] == AppConstants.treatmentTasksTable &&
            item['record_id'] == completed.id)
        .toList();
    expect(queuedTasks, hasLength(1));
    final payload = jsonDecode(
      (await database
          .getPendingSyncItemPayload(queuedTasks.single['id'] as int))!,
    ) as Map<String, dynamic>;
    expect(payload['status'], TaskStatus.completed.value);

    await sync.pushPendingChanges();
    expect(await database.getPendingSyncItems(), isEmpty);
    expect(
      supabase.remoteRows[AppConstants.treatmentTasksTable]!
          .singleWhere((row) => row['id'] == completed.id)['status'],
      TaskStatus.completed.value,
    );
    expect(supabase.remoteCount(AppConstants.treatmentTasksTable), 1);
  });

  test('task sync does not overwrite an already-synced newer cloud treatment',
      () async {
    final supabase = _FakeSupabaseService();
    final sync = SyncService(
      supabaseService: supabase,
      dbHelper: database,
    );
    final rows = _fixtureRows(DateTime.utc(2026, 10, 31, 9));
    await sync.persistQueuedUpserts(_writes(rows));
    await sync.pushPendingChanges();
    expect(await database.getPendingSyncItems(), isEmpty);

    final remoteTreatment =
        supabase.remoteRows[AppConstants.treatmentsTable]!.single;
    remoteTreatment['notes'] = 'Newer cloud treatment notes';
    remoteTreatment['updated_at'] = '2026-11-02T09:00:00.000Z';
    final original = TreatmentTaskModel.fromMap(
        rows[AppConstants.treatmentTasksTable]!.single);
    final completed = original.copyWith(
      status: TaskStatus.completed,
      completedAt: DateTime.utc(2026, 11, 1, 8),
      updatedAt: DateTime.utc(2026, 11, 1, 8),
    );
    await sync.persistQueuedUpserts([
      LocalSyncUpsert(
        tableName: AppConstants.treatmentTasksTable,
        recordId: completed.id,
        localData: completed.toMap(),
        remoteData: _remoteRow(
          AppConstants.treatmentTasksTable,
          completed.toMap(),
        ),
      ),
    ]);
    supabase.upsertedTables.clear();

    await sync.pushPendingChanges();

    expect(supabase.upsertedTables, [AppConstants.treatmentTasksTable]);
    expect(remoteTreatment['notes'], 'Newer cloud treatment notes');
    expect(remoteTreatment['updated_at'], '2026-11-02T09:00:00.000Z');

    remoteTreatment['notes'] = 'Cloud treatment to download';
    final staleRemoteTask =
        supabase.remoteRows[AppConstants.treatmentTasksTable]!.single
          ..['status'] = TaskStatus.pending.value
          ..['completed_at'] = null
          ..['updated_at'] = '2026-10-31T09:00:00.000Z';
    await sync.pullFromRemote(userId: 'offline-user');
    final localTask = TreatmentTaskModel.fromMap(
      (await database.queryById(
          AppConstants.treatmentTasksTable, completed.id))!,
    );
    expect(localTask.status, TaskStatus.completed);
    expect(localTask.completedAt, completed.completedAt);
    expect(
      (await database.queryById(AppConstants.treatmentsTable,
          remoteTreatment['id'] as String))?['notes'],
      'Cloud treatment to download',
    );
    expect(staleRemoteTask['status'], TaskStatus.pending.value);
  });

  test('restored connectivity automatically retries without losing local data',
      () async {
    final supabase = _FakeSupabaseService();
    final connectivity = StreamController<bool>.broadcast();
    addTearDown(connectivity.close);
    final sync = SyncService(
      supabaseService: supabase,
      dbHelper: database,
      connectivityChanges: connectivity.stream,
    );
    final rows = _fixtureRows(DateTime.utc(2026, 10, 31, 9));
    await sync.persistQueuedUpserts(_writes(rows));
    supabase.failUpsertsOnce.add(AppConstants.cropsTable);
    supabase.signedIn = true;

    connectivity.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(supabase.remoteCount(AppConstants.cropsTable), 0);
    expect(await database.getPendingSyncItems(), isNotEmpty);
    expect(
      await database.queryById(AppConstants.cropsTable, 'crop-offline'),
      isNotNull,
    );
    expect(
      await database.queryDiagnosesForCrop('crop-offline'),
      hasLength(1),
    );

    connectivity.add(false);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    connectivity.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(await database.getPendingSyncItems(), isEmpty);
    for (final table in rows.keys) {
      expect(supabase.remoteCount(table), 1, reason: '$table must auto-sync');
    }
  });
}
