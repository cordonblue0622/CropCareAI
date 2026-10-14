import 'package:cropcare_ai/core/constants/app_constants.dart';
import 'package:cropcare_ai/core/constants/app_enums.dart';
import 'package:cropcare_ai/data/local/database_helper.dart';
import 'package:cropcare_ai/data/models/crop_model.dart';
import 'package:cropcare_ai/data/models/treatment_model.dart';
import 'package:cropcare_ai/data/models/treatment_task_model.dart';
import 'package:cropcare_ai/data/remote/supabase_service.dart';
import 'package:cropcare_ai/features/crops/providers/crops_provider.dart';
import 'package:cropcare_ai/services/sync_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _StaleCropSupabaseService extends SupabaseService {
  _StaleCropSupabaseService(this.remoteCrop);

  final Map<String, dynamic> remoteCrop;

  @override
  Future<List<Map<String, dynamic>>> getCrops(String userId) async =>
      [remoteCrop];

  @override
  Future<List<Map<String, dynamic>>> getCropsIncludingDeleted(
          String userId) async =>
      [remoteCrop];

  @override
  Future<List<Map<String, dynamic>>> getDiagnosesByCrop(String cropId) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> getTreatmentsByCrop(String cropId) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> getTreatmentTasksByUser(
          String userId) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> getProgressUpdates(String cropId) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> getNotifications(String userId) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> getChatSessionsByCrop(
          String cropId) async =>
      const [];
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

  test('new crop reports when cloud upload remains queued', () async {
    final now = DateTime.now();
    final supabase = _StaleCropSupabaseService(const {});
    final provider = CropsProvider(
      supabase: supabase,
      db: database,
      sync: _NoopSyncService(
        supabaseService: supabase,
        dbHelper: database,
      ),
    );
    addTearDown(provider.dispose);

    final saved = await provider.addCrop(
      userId: 'user-1',
      cropType: CropType.eggplant,
      cropName: 'Backyard eggplant',
      plantedAt: now,
    );

    expect(saved, isTrue);
    expect(provider.crops, hasLength(1));
    expect(provider.error, contains('cloud sync is still pending'));
    final pending = await database.getPendingSyncItems();
    expect(
      pending.any(
        (item) =>
            item['table_name'] == AppConstants.cropsTable &&
            item['record_id'] == provider.crops.single.id,
      ),
      isTrue,
    );
  });

  test('refresh does not resurrect a newer local crop deletion', () async {
    final createdAt = DateTime.utc(2026, 9, 1);
    final remoteUpdatedAt = DateTime.utc(2026, 9, 10);
    final localDeletedAt = DateTime.utc(2026, 9, 14);
    final remoteCrop = CropModel(
      id: 'crop-1',
      userId: 'user-1',
      cropType: CropType.eggplant,
      cropName: 'Backyard eggplant',
      createdAt: createdAt,
      updatedAt: remoteUpdatedAt,
    );
    final deletedCrop = remoteCrop.copyWith(
      isDeleted: true,
      updatedAt: localDeletedAt,
    );
    await database.upsertRow(AppConstants.cropsTable, deletedCrop.toMap());

    final supabase = _StaleCropSupabaseService(
      remoteCrop.toMap()..['is_deleted'] = false,
    );
    final provider = CropsProvider(
      supabase: supabase,
      db: database,
      sync: _NoopSyncService(
        supabaseService: supabase,
        dbHelper: database,
      ),
    );
    addTearDown(provider.dispose);

    await provider.fetchCrops('user-1');

    expect(provider.crops, isEmpty);
    final stored = await database.queryById(AppConstants.cropsTable, 'crop-1');
    expect(stored?['is_deleted'], 1);
    expect(stored?['updated_at'], localDeletedAt.toIso8601String());
  });

  test('crop deletion queues related records and removes local alerts',
      () async {
    final now = DateTime.utc(2026, 9, 14, 13);
    final crop = CropModel(
      id: 'crop-1',
      userId: 'user-1',
      cropType: CropType.eggplant,
      cropName: 'Backyard eggplant',
      createdAt: now,
      updatedAt: now,
    );
    await database.upsertRow(AppConstants.cropsTable, crop.toMap());
    await database.upsertRow(AppConstants.diagnosesTable, {
      'id': 'diagnosis-1',
      'crop_id': crop.id,
      'user_id': crop.userId,
      'diagnosis_mode': 'offline',
      'disease_name': 'Eggplant Leaf Spot',
      'severity': 'moderate',
      'diagnosed_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await database.upsertRow(AppConstants.chatSessionsTable, {
      'id': 'session-1',
      'user_id': crop.userId,
      'crop_id': crop.id,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await database.upsertRow(AppConstants.chatMessagesTable, {
      'id': 'message-1',
      'session_id': 'session-1',
      'user_id': crop.userId,
      'role': 'assistant',
      'content': 'Saved crop conversation',
      'created_at': now.toIso8601String(),
    });
    await database.upsertRow(AppConstants.treatmentTasksTable, {
      'id': 'task-1',
      'user_id': crop.userId,
      'crop_id': crop.id,
      'treatment_id': 'treatment-1',
      'title': 'Water crop',
      'description': null,
      'due_at': now.toIso8601String(),
      'completed_at': null,
      'status': 'pending',
      'task_order': 0,
      'sync_version': 1,
      'is_deleted': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await database.upsertRow(AppConstants.notificationsTable, {
      'id': 'notification-1',
      'user_id': crop.userId,
      'crop_id': crop.id,
      'type': 'task_due',
      'title': 'Treatment due',
      'body': 'Complete today\'s task.',
      'scheduled_for': now.toIso8601String(),
      'created_at': now.toIso8601String(),
    });

    final supabase = _StaleCropSupabaseService(
      crop.toMap()..['is_deleted'] = false,
    );
    final provider = CropsProvider(
      supabase: supabase,
      db: database,
      sync: _NoopSyncService(
        supabaseService: supabase,
        dbHelper: database,
      ),
    );
    addTearDown(provider.dispose);
    await provider.fetchCrops(crop.userId);

    var localCleanupReached = false;
    expect(
      await provider.deleteCrop(
        crop.id,
        onLocalDelete: () async {
          localCleanupReached = true;
          expect(
            (await database.queryById(
                AppConstants.treatmentTasksTable, 'task-1'))?['is_deleted'],
            1,
          );
          expect(
            await database.queryById(
                AppConstants.notificationsTable, 'notification-1'),
            isNull,
          );
        },
      ),
      isTrue,
    );
    expect(localCleanupReached, isTrue);

    expect(provider.crops, isEmpty);
    expect(
      (await database.queryById(
          AppConstants.diagnosesTable, 'diagnosis-1'))?['is_deleted'],
      1,
    );
    expect(
      (await database.queryById(
          AppConstants.chatSessionsTable, 'session-1'))?['is_deleted'],
      1,
    );
    expect(
      await database.queryById(AppConstants.chatMessagesTable, 'message-1'),
      isNull,
    );
    expect(
      await database.queryById(
          AppConstants.notificationsTable, 'notification-1'),
      isNull,
    );

    final queued = await database.getPendingSyncItems();
    final operationsByRecord = {
      for (final item in queued)
        item['record_id'] as String: item['operation'] as String,
    };
    expect(operationsByRecord['diagnosis-1'], 'SOFT_DELETE');
    expect(operationsByRecord['session-1'], 'SOFT_DELETE');
    expect(operationsByRecord['message-1'], 'DELETE');
    expect(operationsByRecord['notification-1'], 'DELETE');
    expect(operationsByRecord['crop-1'], 'UPSERT');
  });

  test('AI plan revision keeps completed tasks and retires pending tasks',
      () async {
    final now = DateTime(2026, 10, 11, 10);
    final treatment = TreatmentModel(
      id: 'treatment-1',
      cropId: 'crop-1',
      userId: 'user-1',
      diseaseName: 'Eggplant Leaf Spot',
      treatmentTitle: 'Treatment Plan',
      treatmentSteps: const ['Old treatment step'],
      expectedDurationDays: 7,
      status: TreatmentStatus.ongoing,
      startedAt: now.subtract(const Duration(days: 4)),
      createdAt: now.subtract(const Duration(days: 4)),
      updatedAt: now.subtract(const Duration(days: 4)),
    );
    final completedTask = TreatmentTaskModel(
      id: 'completed-task',
      treatmentId: treatment.id,
      cropId: treatment.cropId,
      userId: treatment.userId,
      title: 'Completed historical action',
      dueAt: now.subtract(const Duration(days: 1)),
      completedAt: now.subtract(const Duration(days: 1)),
      status: TaskStatus.completed,
      taskOrder: 1,
      createdAt: now.subtract(const Duration(days: 1)),
      updatedAt: now.subtract(const Duration(days: 1)),
    );
    final pendingTask = TreatmentTaskModel(
      id: 'pending-task',
      treatmentId: treatment.id,
      cropId: treatment.cropId,
      userId: treatment.userId,
      title: 'Old future action',
      dueAt: now.add(const Duration(days: 2)),
      status: TaskStatus.pending,
      taskOrder: 2,
      createdAt: now,
      updatedAt: now,
    );
    await database.upsertRow(AppConstants.treatmentsTable, treatment.toMap());
    await database.upsertRow(
        AppConstants.treatmentTasksTable, completedTask.toMap());
    await database.upsertRow(
        AppConstants.treatmentTasksTable, pendingTask.toMap());

    final supabase = _StaleCropSupabaseService(const {});
    final provider = CropsProvider(
      supabase: supabase,
      db: database,
      sync: _NoopSyncService(
        supabaseService: supabase,
        dbHelper: database,
      ),
    );
    addTearDown(provider.dispose);

    final revision = await provider.reviseRemainingTreatmentPlan(
      treatment: treatment,
      tasks: [completedTask, pendingTask],
      recommendedActions: const [
        'Remove badly affected leaves.',
        'Inspect the plant daily for new spots.',
      ],
      assessment: 'The condition is spreading.',
      healthScore: 38,
      assessedAt: now,
    );

    expect(revision, isNotNull);
    expect(revision!.treatment.source, 'ai-progress-reassessment');
    expect(
      revision.treatment.startedAt,
      DateTime(2026, 10, 12),
    );
    expect(revision.treatment.treatmentSteps, [
      'Remove badly affected leaves.',
      'Inspect the plant daily for new spots.',
    ]);
    expect(revision.tasks.map((task) => task.id), contains('completed-task'));
    expect(
        revision.tasks.map((task) => task.id), isNot(contains('pending-task')));
    expect(
      revision.tasks.any((task) => task.title == 'Old future action'),
      isFalse,
    );
    final retired = await database.queryById(
        AppConstants.treatmentTasksTable, 'pending-task');
    expect(retired?['is_deleted'], 1);
    expect(
      revision.tasks.any(
          (task) => task.title == 'Inspect the plant daily for new spots.'),
      isTrue,
    );
  });
}
