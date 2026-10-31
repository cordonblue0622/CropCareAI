import 'dart:convert';

import 'package:cropcare_ai/core/constants/app_constants.dart';
import 'package:cropcare_ai/core/constants/app_enums.dart';
import 'package:cropcare_ai/data/local/database_helper.dart';
import 'package:cropcare_ai/data/models/chat_message_model.dart';
import 'package:cropcare_ai/data/models/chat_session_model.dart';
import 'package:cropcare_ai/data/models/crop_model.dart';
import 'package:cropcare_ai/data/models/diagnosis_model.dart';
import 'package:cropcare_ai/data/models/treatment_model.dart';
import 'package:cropcare_ai/data/models/treatment_task_model.dart';
import 'package:cropcare_ai/data/remote/supabase_service.dart';
import 'package:cropcare_ai/services/sync_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeSupabaseService extends SupabaseService {
  final remoteRows = <String, List<Map<String, dynamic>>>{};
  final failUpsertsOnce = <String>{};
  int upsertCalls = 0;

  List<Map<String, dynamic>> _rows(String table) =>
      remoteRows[table] ?? const [];

  int remoteCount(String table) => _rows(table).length;

  @override
  Future<void> upsertRecord({
    required String table,
    required Map<String, dynamic> data,
  }) async {
    upsertCalls++;
    if (failUpsertsOnce.remove(table)) {
      throw StateError('simulated $table synchronization failure');
    }
    final rows = remoteRows.putIfAbsent(table, () => []);
    rows.removeWhere((row) => row['id'] == data['id']);
    rows.add(Map<String, dynamic>.from(data));
  }

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
}
