import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_enums.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/bundled_disease_knowledge.dart';
import '../../../data/models/crop_model.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../data/models/chat_session_model.dart';
import '../../../data/models/diagnosis_model.dart';
import '../../../data/models/disease_knowledge_model.dart';
import '../../../data/models/disease_treatment_day_step_model.dart';
import '../../../data/models/progress_update_model.dart';
import '../../../data/models/treatment_model.dart';
import '../../../data/models/treatment_task_model.dart';
import '../../../data/remote/supabase_service.dart';
import '../../../services/health_score_service.dart';
import '../../../services/sync_service.dart';
import '../../../services/treatment_action_parser.dart';
import '../../../services/treatment_plan_service.dart';
import '../../../services/connectivity_service.dart';

class CropsProvider extends ChangeNotifier {
  final SupabaseService _supabase;
  final DatabaseHelper _db;
  final SyncService _sync;
  final ConnectivityService? _connectivity;

  List<CropModel> _crops = [];
  List<DiseaseKnowledgeModel> _diseaseKnowledge = [];
  final Set<String> _planRevisionCheckInsInProgress = {};
  final Set<String> _revisedPlanCheckInIds = {};
  bool _isLoading = false;
  String? _error;
  late final StreamSubscription<void> _remoteCropChangesSubscription;

  CropsProvider({
    required SupabaseService supabase,
    required DatabaseHelper db,
    required SyncService sync,
    ConnectivityService? connectivity,
  })  : _supabase = supabase,
        _db = db,
        _sync = sync,
        _connectivity = connectivity {
    _remoteCropChangesSubscription = _sync.remoteCropChanges.listen((_) {
      final userId = _supabase.currentUser?.id;
      if (userId != null) unawaited(fetchCrops(userId));
    });
  }

  @override
  void dispose() {
    unawaited(_remoteCropChangesSubscription.cancel());
    super.dispose();
  }

  List<CropModel> get crops => _crops;
  List<DiseaseKnowledgeModel> get diseaseKnowledge => _diseaseKnowledge;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<CropModel> get activeCrops => _crops
      .where((c) => c.status != CropStatus.archived && !c.isDeleted)
      .toList();

  List<CropModel> get completedCrops => _crops
      .where((c) => c.status == CropStatus.archived && !c.isDeleted)
      .toList();

  bool hasCropNameConflict({
    required String cropName,
    String? excludingCropId,
  }) {
    final normalizedName = _normalizeCropName(cropName);
    if (normalizedName.isEmpty) {
      return false;
    }

    return _crops.any(
      (crop) =>
          !crop.isDeleted &&
          crop.id != excludingCropId &&
          _normalizeCropName(crop.cropName) == normalizedName,
    );
  }

  String? validateUniqueCropName({
    required String cropName,
    String? excludingCropId,
  }) {
    final trimmedName = cropName.trim();
    if (trimmedName.isEmpty) {
      return 'Required';
    }

    if (hasCropNameConflict(
      cropName: trimmedName,
      excludingCropId: excludingCropId,
    )) {
      return 'Crop name already exists. Use a unique name.';
    }

    return null;
  }

  // ─── Fetch ────────────────────────────────────────────────────────────────

  Future<void> fetchCrops(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    if (kIsWeb) {
      try {
        final remoteRows = await _supabase.getCropsIncludingDeleted(userId);
        _crops = remoteRows
            .map(CropModel.fromMap)
            .where((crop) => !crop.isDeleted)
            .toList();
      } catch (error) {
        _error = 'Could not load crops. Check your internet connection.';
      } finally {
        _isLoading = false;
        notifyListeners();
      }
      return;
    }

    try {
      final localRows = await _db.queryByUserId(
        AppConstants.cropsTable,
        userId,
        includeDeleted: true,
      );
      final visibleLocalRows = localRows.where((row) {
        final deleted = row['is_deleted'];
        return deleted != true && deleted != 1;
      }).toList(growable: false);
      _crops = visibleLocalRows.map(CropModel.fromMap).toList();
      // Loading here means the local screen has not rendered its first
      // snapshot. Remote refresh continues in the background and must not keep
      // My Crops behind a spinner while the device is offline.
      _isLoading = false;
      notifyListeners();

      final remoteRows = await _supabase.getCropsIncludingDeleted(userId);
      final remoteIds = remoteRows
          .map((row) => row['id'] as String?)
          .whereType<String>()
          .toSet();
      final queuedCropIds = (await _db.getPendingSyncItems())
          .where((item) =>
              item['table_name'] == AppConstants.cropsTable &&
              (item['operation'] == 'UPSERT' ||
                  item['operation'] == 'SOFT_DELETE'))
          .map((item) => item['record_id'] as String?)
          .whereType<String>()
          .toSet();

      // Build a map of local updated_at by crop id so we only overwrite local
      // records when the remote version is strictly newer. This prevents a
      // recent check-in (saved locally, not yet synced) from being clobbered
      // by the older remote copy during a dashboard refresh.
      final localUpdatedAtById = <String, String>{};
      for (final row in localRows) {
        final id = (row['id'] as String?)?.trim() ?? '';
        if (id.isNotEmpty) {
          localUpdatedAtById[id] = (row['updated_at'] as String?) ?? '';
        }
      }

      final rowsToUpsert = remoteRows.where((remoteRow) {
        final id = (remoteRow['id'] as String?)?.trim() ?? '';
        if (id.isEmpty) return true;
        if (queuedCropIds.contains(id)) return false;
        final localUpdatedAt = localUpdatedAtById[id] ?? '';
        final remoteUpdatedAt = (remoteRow['updated_at'] as String?) ?? '';
        // Compare instants rather than ISO strings: device-local and UTC
        // timestamps can represent the same moment with different offsets.
        return SyncService.remoteTimestampIsAtLeastAsNew(
          remoteTimestamp: remoteUpdatedAt,
          localTimestamp: localUpdatedAt,
        );
      }).toList();

      // Local-only active crops are commonly edits waiting for their first
      // successful sync. Preserve them and queue an idempotent cloud upsert so
      // they survive a later reinstall and appear in the admin console.
      var queuedMissingCrop = false;
      for (final row in visibleLocalRows) {
        final id = (row['id'] as String?)?.trim() ?? '';
        if (id.isEmpty ||
            remoteIds.contains(id) ||
            queuedCropIds.contains(id)) {
          continue;
        }
        final crop = CropModel.fromMap(row);
        await _sync.queueUpsert(
          tableName: AppConstants.cropsTable,
          recordId: crop.id,
          data: _remoteMap(crop),
        );
        queuedMissingCrop = true;
      }

      if (rowsToUpsert.isNotEmpty) {
        await _db.upsertRows(AppConstants.cropsTable, rowsToUpsert);
      }
      if (queuedMissingCrop) await _attemptSync();

      final mergedRows =
          await _db.queryByUserId(AppConstants.cropsTable, userId);
      _crops = mergedRows.map(CropModel.fromMap).toList();
    } catch (_) {
      // Fall back to local cache
      final rows = await _db.queryByUserId(AppConstants.cropsTable, userId);
      _crops = rows.map(CropModel.fromMap).toList();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Add ──────────────────────────────────────────────────────────────────

  Future<bool> addCrop({
    required String userId,
    required CropType cropType,
    required String cropName,
    String? plotCode,
    String? locationLabel,
    String? notes,
    DateTime? plantedAt,
  }) async {
    try {
      _error = null;
      _error = validateUniqueCropName(cropName: cropName);
      if (_error != null) {
        notifyListeners();
        return false;
      }

      final now = DateTime.now();
      final crop = CropModel(
        id: const Uuid().v4(),
        userId: userId,
        cropType: cropType,
        cropName: cropName,
        plotCode: plotCode,
        locationLabel: locationLabel,
        notes: notes,
        status: CropStatus.monitoring,
        plantedAt: plantedAt,
        syncVersion: 1,
        createdAt: now,
        updatedAt: now,
      );

      await _upsertLocallyAndQueue(
        table: AppConstants.cropsTable,
        recordId: crop.id,
        localData: crop.toMap(),
        remoteData: _remoteMap(crop),
      );
      _crops.insert(0, crop);
      notifyListeners();
      await _attemptSync();
      final pending = await _pendingCropSyncItems(crop.id);
      if (pending.isNotEmpty) {
        _error =
            "Crop saved successfully on this device. It will automatically sync when you're back online.";
        final lastError = pending.last['last_error'] as String?;
        debugPrint(
          '[CropsProvider] Crop ${crop.id} is still waiting to sync.'
          '${lastError == null || lastError.isEmpty ? '' : ' Last error: $lastError'}',
        );
        notifyListeners();
      }
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ─── Update ───────────────────────────────────────────────────────────────

  Future<bool> updateCrop(CropModel crop, {bool syncNow = true}) async {
    try {
      _error = validateUniqueCropName(
        cropName: crop.cropName,
        excludingCropId: crop.id,
      );
      if (_error != null) {
        notifyListeners();
        return false;
      }

      final updated = crop.copyWith(updatedAt: DateTime.now());
      await _upsertLocallyAndQueue(
        table: AppConstants.cropsTable,
        recordId: updated.id,
        localData: updated.toMap(),
        remoteData: _remoteMap(updated),
      );
      final idx = _crops.indexWhere((c) => c.id == updated.id);
      if (idx != -1) _crops[idx] = updated;
      notifyListeners();
      if (syncNow) {
        await _attemptSync();
      }
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ─── Delete ───────────────────────────────────────────────────────────────

  Future<bool> deleteCrop(
    String cropId, {
    Future<void> Function()? onLocalDelete,
  }) async {
    if (kIsWeb) {
      return _deleteCropOnWeb(cropId, onLocalDelete: onLocalDelete);
    }

    try {
      final crop = _crops.cast<CropModel?>().firstWhere(
            (item) => item?.id == cropId,
            orElse: () => null,
          );
      CropModel? cropToDelete = crop;
      if (cropToDelete == null && !kIsWeb) {
        final localRow = await _db.queryById(AppConstants.cropsTable, cropId);
        if (localRow != null) cropToDelete = CropModel.fromMap(localRow);
      }
      if (cropToDelete == null) {
        final userId = _supabase.currentUser?.id;
        if (userId != null) {
          final remoteRow = await _supabase.getCropById(
            userId: userId,
            cropId: cropId,
          );
          if (remoteRow != null) cropToDelete = CropModel.fromMap(remoteRow);
        }
      }
      if (cropToDelete == null) {
        _error = 'Could not find this crop.';
        notifyListeners();
        return false;
      }

      final localDb = await _db.database;
      final diagnosisRows = await localDb.query(
        AppConstants.diagnosesTable,
        where: 'crop_id = ?',
        whereArgs: [cropId],
      );
      final treatmentRows = await localDb.query(
        AppConstants.treatmentsTable,
        where: 'crop_id = ?',
        whereArgs: [cropId],
      );
      final taskRows = await localDb.query(
        AppConstants.treatmentTasksTable,
        where: 'crop_id = ?',
        whereArgs: [cropId],
      );
      final progressRows = await localDb.query(
        AppConstants.progressUpdatesTable,
        where: 'crop_id = ?',
        whereArgs: [cropId],
      );
      final notificationRows = await localDb.query(
        AppConstants.notificationsTable,
        where: 'crop_id = ?',
        whereArgs: [cropId],
      );
      final sessionRows = await localDb.query(
        AppConstants.chatSessionsTable,
        where: 'crop_id = ?',
        whereArgs: [cropId],
      );
      final sessionIds = sessionRows
          .map((row) => row['id'] as String?)
          .whereType<String>()
          .toList(growable: false);
      final chatMessageIds = <String>[];
      for (final sessionId in sessionIds) {
        final rows = await localDb.query(
          AppConstants.chatMessagesTable,
          where: 'session_id = ?',
          whereArgs: [sessionId],
        );
        chatMessageIds.addAll(
          rows.map((row) => row['id'] as String?).whereType<String>(),
        );
      }

      await _softDeleteLocalRows(AppConstants.diagnosesTable, diagnosisRows);
      await _softDeleteLocalRows(AppConstants.treatmentsTable, treatmentRows);
      await _softDeleteLocalRows(AppConstants.treatmentTasksTable, taskRows);
      await _softDeleteLocalRows(
          AppConstants.progressUpdatesTable, progressRows);
      await _softDeleteLocalRows(AppConstants.chatSessionsTable, sessionRows);
      await _hardDeleteLocalRows(
        AppConstants.notificationsTable,
        notificationRows.map((row) => row['id'] as String?).whereType<String>(),
      );
      await _hardDeleteLocalRows(
          AppConstants.chatMessagesTable, chatMessageIds);

      final deletedCrop = cropToDelete.copyWith(
        isDeleted: true,
        updatedAt: DateTime.now(),
      );
      await _upsertLocallyAndQueue(
        table: AppConstants.cropsTable,
        recordId: deletedCrop.id,
        localData: deletedCrop.toMap(),
        remoteData: _remoteMap(deletedCrop),
      );
      _crops.removeWhere((c) => c.id == cropId);
      notifyListeners();
      if (onLocalDelete != null) {
        try {
          await onLocalDelete();
        } catch (_) {}
      }
      try {
        await _deleteCropRemotely(cropToDelete);
      } catch (_) {
        // Local tombstones and queued deletes remain authoritative offline.
      }
      await _attemptSync();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> _deleteCropOnWeb(
    String cropId, {
    Future<void> Function()? onLocalDelete,
  }) async {
    final crop = _crops.cast<CropModel?>().firstWhere(
          (item) => item?.id == cropId,
          orElse: () => null,
        );
    if (crop == null) {
      _error = 'Could not find this crop.';
      notifyListeners();
      return false;
    }

    try {
      await _deleteCropRemotely(crop, deleteCrop: true);
      _crops.removeWhere((item) => item.id == cropId);
      _error = null;
      notifyListeners();
      if (onLocalDelete != null) {
        try {
          await onLocalDelete();
        } catch (_) {}
      }
      return true;
    } catch (error) {
      _error = 'Could not delete this crop. Please try again.';
      notifyListeners();
      return false;
    }
  }

  Future<void> _deleteCropRemotely(
    CropModel crop, {
    bool deleteCrop = false,
  }) async {
    final remoteDiagnosisRows = await _supabase.getDiagnosesByCrop(crop.id);
    final remoteTreatmentRows = await _supabase.getTreatmentsByCrop(crop.id);
    final remoteProgressRows = await _supabase.getProgressUpdates(crop.id);
    final remoteTaskRows =
        (await _supabase.getTreatmentTasksByUser(crop.userId))
            .where((row) => row['crop_id'] == crop.id)
            .toList(growable: false);
    final remoteNotificationIds =
        (await _supabase.getNotifications(crop.userId))
            .where((row) => row['crop_id'] == crop.id)
            .map((row) => row['id'] as String?)
            .whereType<String>()
            .toList(growable: false);
    final remoteSessionRows = await _supabase.getChatSessionsByCrop(crop.id);
    final remoteSessionIds = remoteSessionRows
        .map((row) => row['id'] as String?)
        .whereType<String>()
        .toList(growable: false);
    final remoteChatMessageIds = <String>[];
    for (final sessionId in remoteSessionIds) {
      final rows = await _supabase.getChatMessages(sessionId);
      remoteChatMessageIds.addAll(
        rows.map((row) => row['id'] as String?).whereType<String>(),
      );
    }

    await _softDeleteRemoteRows(
        AppConstants.diagnosesTable, remoteDiagnosisRows);
    await _softDeleteRemoteRows(
        AppConstants.treatmentsTable, remoteTreatmentRows);
    await _softDeleteRemoteRows(
        AppConstants.treatmentTasksTable, remoteTaskRows);
    await _softDeleteRemoteRows(
        AppConstants.progressUpdatesTable, remoteProgressRows);
    await _softDeleteRemoteRows(
        AppConstants.chatSessionsTable, remoteSessionRows);
    await _hardDeleteRemoteRows(
        AppConstants.notificationsTable, remoteNotificationIds);
    await _hardDeleteRemoteRows(
        AppConstants.chatMessagesTable, remoteChatMessageIds);
    if (deleteCrop) await _supabase.softDeleteCrop(crop.id);
  }

  Future<void> _softDeleteRemoteRows(
    String table,
    Iterable<Map<String, dynamic>> rows,
  ) async {
    final now = DateTime.now().toIso8601String();
    for (final row in rows) {
      final id = row['id'] as String?;
      if (id == null || id.isEmpty) {
        continue;
      }
      final updated = Map<String, dynamic>.from(row)
        ..['id'] = id
        ..['is_deleted'] = true
        ..['updated_at'] = now;
      await _supabase.upsertRecord(table: table, data: updated);
    }
  }

  Future<void> _softDeleteLocalRows(
    String table,
    Iterable<Map<String, dynamic>> rows,
  ) async {
    final now = DateTime.now().toIso8601String();
    for (final row in rows) {
      final id = row['id'] as String?;
      if (id == null || id.isEmpty) {
        continue;
      }
      final updated = Map<String, dynamic>.from(row)
        ..['id'] = id
        ..['is_deleted'] = 1;
      if (updated.containsKey('updated_at')) {
        updated['updated_at'] = now;
      }
      await _db.upsertRow(table, updated);
      await _sync.queueSoftDelete(
        tableName: table,
        recordId: id,
        userId: updated['user_id'] as String?,
      );
    }
  }

  Future<void> _hardDeleteRemoteRows(
    String table,
    Iterable<String> ids,
  ) async {
    for (final id in ids) {
      await _supabase.deleteRecord(table: table, id: id);
    }
  }

  Future<void> _hardDeleteLocalRows(
    String table,
    Iterable<String> ids,
  ) async {
    for (final id in ids) {
      final existing = await _db.queryById(table, id);
      await _db.hardDelete(table, id);
      await _sync.queueDelete(
        tableName: table,
        recordId: id,
        userId: existing?['user_id'] as String?,
      );
    }
  }

  String _normalizeCropName(String value) => value.trim().toLowerCase();

  // ─── Helper ───────────────────────────────────────────────────────────────

  /// Converts a CropModel to a map suitable for Supabase (boolean vs int).
  Map<String, dynamic> _remoteMap(CropModel c) {
    final m = c.toMap();
    m['is_deleted'] = c.isDeleted;
    m.remove('provider');
    return m;
  }

  Map<String, dynamic> _diagnosisRemoteMap(DiagnosisModel diagnosis) {
    final map = diagnosis.toMap();
    map['is_deleted'] = diagnosis.isDeleted;
    return map;
  }

  Map<String, dynamic> _treatmentRemoteMap(TreatmentModel treatment) {
    final map = treatment.toMap();
    final rawSteps = map['treatment_steps'];
    if (rawSteps is String && rawSteps.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSteps);
        if (decoded is List) {
          map['treatment_steps'] =
              decoded.map((step) => step.toString()).toList();
        }
      } catch (_) {
        map['treatment_steps'] = treatment.treatmentSteps;
      }
    } else {
      map['treatment_steps'] = treatment.treatmentSteps;
    }

    map['reassessment_required'] = treatment.reassessmentRequired;
    map['is_deleted'] = treatment.isDeleted;

    if (treatment.diagnosisId == null || treatment.diagnosisId!.isEmpty) {
      map.remove('diagnosis_id');
    }

    return map;
  }

  Map<String, dynamic> _treatmentTaskRemoteMap(TreatmentTaskModel task) {
    final map = task.toMap();
    map['is_deleted'] = task.isDeleted;
    return map;
  }

  Future<void> _upsertLocallyAndQueue({
    required String table,
    required String recordId,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
  }) {
    return _upsertAllLocallyAndQueue([
      LocalSyncUpsert(
        tableName: table,
        recordId: recordId,
        localData: localData,
        remoteData: remoteData,
      ),
    ]);
  }

  Future<void> _upsertAllLocallyAndQueue(
    List<LocalSyncUpsert> writes,
  ) async {
    if (kIsWeb) {
      for (final write in writes) {
        await _supabase.upsertRecord(
          table: write.tableName,
          data: write.remoteData,
        );
      }
      return;
    }

    await _sync.persistQueuedUpserts(writes);
  }

  Future<bool> retryCropSync(String cropId) async {
    await _attemptSync();
    final pending = await _pendingCropSyncItems(cropId);
    _error = pending.isEmpty
        ? null
        : "Crop saved successfully on this device. It will automatically sync when you're back online.";
    if (pending.isNotEmpty) {
      final lastError = pending.last['last_error'] as String?;
      debugPrint(
        '[CropsProvider] Crop $cropId is still waiting to sync.'
        '${lastError == null || lastError.isEmpty ? '' : ' Last error: $lastError'}',
      );
    }
    notifyListeners();
    return pending.isEmpty;
  }

  Future<List<Map<String, dynamic>>> _pendingCropSyncItems(
    String cropId,
  ) async {
    if (kIsWeb) return const [];
    return (await _db.getPendingSyncItems())
        .where(
          (item) =>
              item['table_name'] == AppConstants.cropsTable &&
              item['record_id'] == cropId,
        )
        .toList(growable: false);
  }

  Future<void> _attemptSync() async {
    if (!_supabase.isSignedIn) {
      return;
    }
    try {
      if (_connectivity != null && !await _connectivity.isConnected) return;
      await _sync.syncAll();
    } catch (error, stackTrace) {
      // Local state is already committed; the queue will retry later.
      debugPrint(
        '[CropsProvider] Cloud sync attempt failed: $error\n$stackTrace',
      );
    }
  }

  void clear() {
    _crops = [];
    _diseaseKnowledge = [];
    notifyListeners();
  }

  // ─── Add Crop from Diagnosis ───────────────────────────────────────────────

  /// Creates a crop, treatment, and treatment tasks from a scan diagnosis.
  /// Returns the new [CropModel] id on success, null on failure.
  Future<String?> addCropFromDiagnosis({
    required String userId,
    required String diseaseName,
    required String labelKey,
    required String cropName,
    required CropType cropType,
    required Severity severity,
    List<String> treatmentSteps = const [],
    String? initialSummary,
    double? confidenceScore,
    String? resultLabel,
    String? modelName,
    String? modelVersion,
    String? imageUrl,
    Map<String, dynamic>? detectedRegionsJson,
    String? videoUrl,
    DiagnosisMode diagnosisMode = DiagnosisMode.online,
    String? diagnosisId,
    DateTime? diagnosedAt,
    String? chatSessionId,
    String? locationLabel,
    String? notes,
    DateTime? plantedAt,
  }) async {
    try {
      _error = null;
      var normalizedDiseaseName = diseaseName.trim();
      if (normalizedDiseaseName.isEmpty && labelKey.trim().isNotEmpty) {
        final labelKnowledge = await _findLocalDiseaseKnowledge(
          cropType: cropType,
          diseaseName: '',
          labelKey: labelKey,
        );
        normalizedDiseaseName = labelKnowledge?.diseaseName.trim() ?? '';
      }

      // A crop can be added without a diagnosis. In that case the crop row
      // itself is the durable addition audit event; never invent a condition
      // just to create a diagnosis row.
      if (normalizedDiseaseName.isEmpty) {
        final added = await addCrop(
          userId: userId,
          cropType: cropType,
          cropName: cropName.trim(),
          locationLabel: locationLabel,
          notes: notes,
          plantedAt: plantedAt,
        );
        if (!added) return null;
        return _crops
            .where((crop) =>
                crop.userId == userId && crop.cropName == cropName.trim())
            .firstOrNull
            ?.id;
      }

      _error = validateUniqueCropName(cropName: cropName);
      if (_error != null) {
        notifyListeners();
        return null;
      }

      final now = DateTime.now();
      final cropId = const Uuid().v4();

      // Initial health score based on severity
      final initialScore = switch (severity) {
        Severity.healthy => 100.0,
        Severity.severe => 25.0,
        Severity.moderate => 50.0,
        Severity.mild => 70.0,
      };

      final crop = CropModel(
        id: cropId,
        userId: userId,
        cropType: cropType,
        cropName: cropName,
        locationLabel: locationLabel,
        notes: notes,
        status: CropStatus.monitoring,
        plantedAt: plantedAt,
        latestHealthScore: initialScore,
        latestProgressStatus: ProgressStatus.insufficientData,
        createdAt: now,
        updatedAt: now,
      );

      final pendingWrites = <LocalSyncUpsert>[
        LocalSyncUpsert(
          tableName: AppConstants.cropsTable,
          recordId: crop.id,
          localData: crop.toMap(),
          remoteData: _remoteMap(crop),
        ),
      ];

      String? linkedChatSessionId = chatSessionId;
      if (!kIsWeb && chatSessionId != null && chatSessionId.isNotEmpty) {
        final session = await _db.queryById(
          AppConstants.chatSessionsTable,
          chatSessionId,
        );
        if (session == null) {
          // A chat message may already be durable even if an earlier partial
          // save omitted its session row. Rebuild that same session ID from
          // its saved messages so the diagnosis retains an exact conversation
          // link through offline persistence and cloud synchronization.
          final messageRows = (await _db.queryChatMessages(chatSessionId))
              .where((row) => row['user_id'] == userId)
              .toList(growable: false);
          final messageTimes = messageRows
              .map((row) => DateTime.tryParse(
                    row['created_at'] as String? ?? '',
                  ))
              .whereType<DateTime>()
              .toList()
            ..sort();
          if (messageRows.isEmpty) {
            linkedChatSessionId = null;
          } else {
            final recoveredSession = ChatSessionModel(
              id: chatSessionId,
              userId: userId,
              cropId: cropId,
              title: 'Crop consultation',
              isOfflineSession: diagnosisMode == DiagnosisMode.offline,
              lastMessageAt: messageTimes.isEmpty ? now : messageTimes.last,
              createdAt: messageTimes.isEmpty ? now : messageTimes.first,
              updatedAt: now,
            );
            final localSession = recoveredSession.toMap();
            final remoteSession = Map<String, dynamic>.from(localSession)
              ..['is_offline_session'] = recoveredSession.isOfflineSession
              ..['is_deleted'] = recoveredSession.isDeleted;
            pendingWrites.add(
              LocalSyncUpsert(
                tableName: AppConstants.chatSessionsTable,
                recordId: chatSessionId,
                localData: localSession,
                remoteData: remoteSession,
              ),
            );
          }
        } else {
          final localSession = Map<String, dynamic>.from(session)
            ..['crop_id'] = cropId
            ..['updated_at'] = now.toIso8601String();
          final remoteSession = Map<String, dynamic>.from(localSession)
            ..['is_offline_session'] = session['is_offline_session'] == true ||
                    session['is_offline_session'] == 1
                ? true
                : false
            ..['is_deleted'] =
                session['is_deleted'] == true || session['is_deleted'] == 1
                    ? true
                    : false;
          pendingWrites.add(
            LocalSyncUpsert(
              tableName: AppConstants.chatSessionsTable,
              recordId: chatSessionId,
              localData: localSession,
              remoteData: remoteSession,
            ),
          );
        }
      }

      var storedDiagnosisId = diagnosisId?.trim() ?? '';
      if (storedDiagnosisId.isEmpty ||
          await _db.queryById(AppConstants.diagnosesTable, storedDiagnosisId) !=
              null) {
        // Reusing a diagnosis ID from another crop would overwrite its crop
        // relationship. Each crop receives one stable diagnosis ID of its own.
        storedDiagnosisId = const Uuid().v4();
      }

      final diagnosis = DiagnosisModel(
        id: storedDiagnosisId,
        cropId: cropId,
        userId: userId,
        chatSessionId: linkedChatSessionId,
        diagnosisMode: diagnosisMode,
        labelKey: labelKey.isEmpty ? null : labelKey,
        diseaseName: normalizedDiseaseName,
        confidenceScore: confidenceScore,
        severity: severity,
        resultLabel: resultLabel,
        summary: initialSummary?.trim().isEmpty == true
            ? null
            : initialSummary?.trim(),
        imageUrl: imageUrl,
        detectedRegionsJson: detectedRegionsJson,
        videoUrl: videoUrl,
        modelName: modelName,
        modelVersion: modelVersion,
        diagnosedAt: diagnosedAt ?? now,
        createdAt: diagnosedAt ?? now,
        updatedAt: now,
      );

      pendingWrites.add(
        LocalSyncUpsert(
          tableName: AppConstants.diagnosesTable,
          recordId: diagnosis.id,
          localData: diagnosis.toMap(),
          remoteData: _diagnosisRemoteMap(diagnosis),
        ),
      );

      final normalizedTreatmentSteps = _normalizeTreatmentSteps(treatmentSteps);
      final knowledge = await _findLocalDiseaseKnowledge(
        cropType: cropType,
        diseaseName: normalizedDiseaseName,
        labelKey: labelKey,
      );
      final expectedDurationDays = knowledge?.estimatedRecoveryDays ??
          _expectedDurationFor(
            labelKey: labelKey,
            cropType: cropType,
          );
      final protocolSteps = knowledge == null
          ? const <DiseaseTreatmentDayStepModel>[]
          : await _loadLocalTreatmentProtocol(knowledge.id);
      final usesReviewedProtocol = normalizedTreatmentSteps.isEmpty &&
          TreatmentPlanService.coversExpectedDuration(
            daySteps: protocolSteps,
            expectedDurationDays: expectedDurationDays,
          );
      final effectiveTreatmentSteps = normalizedTreatmentSteps.isNotEmpty
          ? normalizedTreatmentSteps
          : _normalizeTreatmentSteps(
              knowledge?.treatmentSteps ?? const <String>[],
            );

      // Create treatment
      if (effectiveTreatmentSteps.isNotEmpty || usesReviewedProtocol) {
        final treatmentId = const Uuid().v4();
        final plan = usesReviewedProtocol
            ? TreatmentPlanService.buildFromDaySteps(
                daySteps: protocolSteps,
                startDate: now,
                expectedDurationDays: expectedDurationDays,
              )
            : TreatmentPlanService.build(
                treatmentSteps: effectiveTreatmentSteps,
                startDate: now,
                expectedDurationDays: expectedDurationDays,
              );
        final isHealthyPlan = severity == Severity.healthy ||
            normalizedDiseaseName.toLowerCase().contains('healthy');
        final treatment = TreatmentModel(
          id: treatmentId,
          cropId: cropId,
          diagnosisId: diagnosis.id,
          userId: userId,
          diseaseName: normalizedDiseaseName,
          treatmentTitle: isHealthyPlan
              ? 'Daily Care Plan — ${cropType.name[0].toUpperCase()}${cropType.name.substring(1)}'
              : 'Treatment Plan — $normalizedDiseaseName',
          treatmentSteps: plan.sourceSteps,
          expectedDurationDays: plan.durationDays,
          status: TreatmentStatus.ongoing,
          startedAt: now,
          source: usesReviewedProtocol ? 'disease-protocol' : 'ai-diagnosis',
          createdAt: now,
          updatedAt: now,
        );

        pendingWrites.add(
          LocalSyncUpsert(
            tableName: AppConstants.treatmentsTable,
            recordId: treatment.id,
            localData: treatment.toMap(),
            remoteData: _treatmentRemoteMap(treatment),
          ),
        );

        // Expand recurring instructions into dated task instances so the plan
        // works offline, in notifications, and in the calendar without a
        // background recurrence scheduler.
        for (var i = 0; i < plan.tasks.length; i++) {
          final plannedTask = plan.tasks[i];
          final task = TreatmentTaskModel(
            id: const Uuid().v4(),
            treatmentId: treatmentId,
            cropId: cropId,
            userId: userId,
            title: plannedTask.title,
            description: plannedTask.description,
            dueAt: plannedTask.dueAt,
            status: TaskStatus.pending,
            taskOrder: i + 1,
            createdAt: now,
            updatedAt: now,
          );
          pendingWrites.add(
            LocalSyncUpsert(
              tableName: AppConstants.treatmentTasksTable,
              recordId: task.id,
              localData: task.toMap(),
              remoteData: _treatmentTaskRemoteMap(task),
            ),
          );
        }
      }

      await _upsertAllLocallyAndQueue(pendingWrites);
      _crops.insert(0, crop);
      notifyListeners();
      await _attemptSync();
      final pending = await _pendingCropSyncItems(crop.id);
      if (pending.isNotEmpty) {
        _error =
            "Crop saved successfully on this device. It will automatically sync when you're back online.";
        final lastError = pending.last['last_error'] as String?;
        debugPrint(
          '[CropsProvider] Crop ${crop.id} is still waiting to sync.'
          '${lastError == null || lastError.isEmpty ? '' : ' Last error: $lastError'}',
        );
        notifyListeners();
      }
      return cropId;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Updates crop health score after a progress check-in.
  Future<void> updateCropHealthScore(
    String cropId,
    double score,
    ProgressStatus status, {
    bool syncNow = true,
  }) async {
    final idx = _crops.indexWhere((c) => c.id == cropId);
    if (idx == -1) return;
    final updated = _crops[idx].copyWith(
      latestHealthScore: score,
      latestProgressStatus: status,
      lastCheckedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await updateCrop(updated, syncNow: syncNow);
  }

  /// Mark a treatment task as completed both remotely (via Supabase) and
  /// in the local SQLite cache. Falls back to local-only if the remote
  /// call fails.
  ///
  /// Returns the updated task on success, or `null` on full failure.
  Future<TreatmentTaskModel?> markTaskDone(
    String taskId, {
    bool recomputeHealthScore = true,
    bool syncNow = true,
  }) async {
    final now = DateTime.now();
    try {
      _error = null;
      if (kIsWeb) {
        final userId = _supabase.currentUser?.id;
        if (userId == null) {
          return null;
        }
        final taskRows = await _supabase.getTreatmentTasksByUser(userId);
        final taskRow = taskRows.cast<Map<String, dynamic>?>().firstWhere(
              (row) => row?['id'] == taskId,
              orElse: () => null,
            );
        if (taskRow == null) {
          return null;
        }
        await _supabase.markTreatmentTaskCompleted(taskId, completedAt: now);
        final updated = TreatmentTaskModel.fromMap(taskRow).copyWith(
          status: TaskStatus.completed,
          completedAt: now,
          updatedAt: now,
        );
        await fetchCrops(userId);
        return updated;
      }

      final database = await _db.database;
      final rows = await database.query(
        AppConstants.treatmentTasksTable,
        where: 'id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final original = TreatmentTaskModel.fromMap(rows.first);
      final updated = original.copyWith(
        status: TaskStatus.completed,
        completedAt: now,
        updatedAt: now,
      );
      await _upsertLocallyAndQueue(
        table: AppConstants.treatmentTasksTable,
        recordId: updated.id,
        localData: updated.toMap(),
        remoteData: _treatmentTaskRemoteMap(updated),
      );
      if (recomputeHealthScore) {
        await recomputeHealthScoreForCrop(updated.cropId);
      }
      notifyListeners();
      if (syncNow) {
        await _attemptSync();
      }
      return updated;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Reanchors treatment tasks when a farmer begins later than the originally
  /// recommended Day 1. Completion timestamps and statuses are retained so
  /// the moved Day 1 remains green in the calendar history.
  Future<TreatmentTimelineRebaseResult> rebaseTreatmentTimeline({
    required TreatmentModel treatment,
    required List<TreatmentTaskModel> tasks,
    required DateTime startedAt,
    bool syncNow = true,
  }) async {
    final previousStart = treatment.startedAt ?? treatment.createdAt;
    final normalizedStart = DateTime(
      startedAt.year,
      startedAt.month,
      startedAt.day,
      previousStart.hour,
      previousStart.minute,
    );
    final now = DateTime.now();
    final updatedTreatment = treatment.copyWith(
      startedAt: normalizedStart,
      updatedAt: now,
    );
    await _upsertLocallyAndQueue(
      table: AppConstants.treatmentsTable,
      recordId: updatedTreatment.id,
      localData: updatedTreatment.toMap(),
      remoteData: _treatmentRemoteMap(updatedTreatment),
    );

    final updatedTasks = <TreatmentTaskModel>[];
    for (final task in tasks) {
      if (task.treatmentId != treatment.id || task.isDeleted) {
        updatedTasks.add(task);
        continue;
      }

      final updatedTask = task.copyWith(
        dueAt: TreatmentPlanService.rebaseTaskDate(
          originalDueAt: task.dueAt,
          originalStartAt: previousStart,
          newStartAt: normalizedStart,
        ),
        updatedAt: now,
      );
      await _upsertLocallyAndQueue(
        table: AppConstants.treatmentTasksTable,
        recordId: updatedTask.id,
        localData: updatedTask.toMap(),
        remoteData: _treatmentTaskRemoteMap(updatedTask),
      );
      updatedTasks.add(updatedTask);
    }

    notifyListeners();
    if (syncNow) {
      await _attemptSync();
    }
    return TreatmentTimelineRebaseResult(
      treatment: updatedTreatment,
      tasks: updatedTasks,
    );
  }

  /// Migrates legacy reviewed-protocol tasks that stored a day's action list
  /// in a single task into separately checkable task rows. Deterministic child
  /// IDs make this safe to retry if a sync is interrupted partway through.
  Future<List<TreatmentTaskModel>> expandLegacyProtocolTasks(
    List<TreatmentTaskModel> tasks, {
    bool syncNow = false,
  }) async {
    final expanded = <TreatmentTaskModel>[];
    final tasksById = {for (final task in tasks) task.id: task};
    var changed = false;
    final dayTitle = RegExp(r'^Day\s+\d+\s*:', caseSensitive: false);
    final actionLine = RegExp(r'^\s*-\s+(.+?)\s*$');

    for (final task in tasks) {
      if (task.isDeleted) continue;
      final description = task.description?.trim() ?? '';
      final actions = description
          .split('\n')
          .map((line) => actionLine.firstMatch(line)?.group(1)?.trim())
          .whereType<String>()
          .where((line) => line.isNotEmpty)
          .toList(growable: false);

      if (!dayTitle.hasMatch(task.title.trim()) || actions.length < 2) {
        expanded.add(task);
        continue;
      }

      changed = true;
      final contextDescription = description
          .split('\n')
          .where((line) => !actionLine.hasMatch(line))
          .join('\n')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
      final now = DateTime.now();
      for (var index = 0; index < actions.length; index++) {
        final childId = const Uuid().v5(
          Namespace.url.value,
          'cropcareai:protocol-task:${task.id}:${index + 1}',
        );
        final existingChild = tasksById[childId];
        final child = existingChild ??
            task.copyWith(
              id: childId,
              title: actions[index],
              description:
                  contextDescription.isEmpty ? null : contextDescription,
              taskOrder: task.taskOrder == null
                  ? index + 1
                  : task.taskOrder! * 100 + index + 1,
              updatedAt: now,
            );
        if (existingChild == null) {
          await _upsertLocallyAndQueue(
            table: AppConstants.treatmentTasksTable,
            recordId: child.id,
            localData: child.toMap(),
            remoteData: _treatmentTaskRemoteMap(child),
          );
        }
        expanded.add(child);
      }

      final retired = task.copyWith(
        isDeleted: true,
        syncVersion: task.syncVersion + 1,
        updatedAt: now,
      );
      await _upsertLocallyAndQueue(
        table: AppConstants.treatmentTasksTable,
        recordId: retired.id,
        localData: retired.toMap(),
        remoteData: _treatmentTaskRemoteMap(retired),
      );
    }

    if (changed) {
      notifyListeners();
      if (syncNow) await _attemptSync();
    }
    return expanded;
  }

  /// Moves a missed treatment day and all remaining pending days to the date
  /// the farmer actually submitted the check-in. Completed earlier days keep
  /// their historical dates.
  Future<TreatmentTimelineRebaseResult> shiftTreatmentTimelineFrom({
    required TreatmentModel treatment,
    required List<TreatmentTaskModel> tasks,
    required DateTime fromDate,
    required DateTime toDate,
    bool syncNow = true,
  }) async {
    final scheduledDay = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final submittedDay = DateTime(toDate.year, toDate.month, toDate.day);
    final shiftDays = submittedDay.difference(scheduledDay).inDays;
    if (shiftDays <= 0) {
      return TreatmentTimelineRebaseResult(treatment: treatment, tasks: tasks);
    }

    final now = DateTime.now();
    final shiftedTasks = <TreatmentTaskModel>[];
    for (final task in tasks) {
      if (task.treatmentId != treatment.id || task.isDeleted) {
        shiftedTasks.add(task);
        continue;
      }

      final taskDay =
          DateTime(task.dueAt.year, task.dueAt.month, task.dueAt.day);
      final isSubmittedDay = taskDay == scheduledDay;
      if (taskDay.isBefore(scheduledDay) ||
          (task.status == TaskStatus.completed && !isSubmittedDay)) {
        shiftedTasks.add(task);
        continue;
      }

      final shifted = task.copyWith(
        dueAt: task.dueAt.add(Duration(days: shiftDays)),
        syncVersion: task.syncVersion + 1,
        updatedAt: now,
      );
      await _upsertLocallyAndQueue(
        table: AppConstants.treatmentTasksTable,
        recordId: shifted.id,
        localData: shifted.toMap(),
        remoteData: _treatmentTaskRemoteMap(shifted),
      );
      shiftedTasks.add(shifted);
    }

    notifyListeners();
    if (syncNow) await _attemptSync();
    return TreatmentTimelineRebaseResult(
      treatment: treatment,
      tasks: shiftedTasks,
    );
  }

  Future<void> saveProgressUpdate(
    ProgressUpdateModel update, {
    bool syncNow = true,
  }) async {
    _error = null;
    await _upsertLocallyAndQueue(
      table: AppConstants.progressUpdatesTable,
      recordId: update.id,
      localData: update.toMap(),
      remoteData: update.toRemoteMap()..['is_deleted'] = update.isDeleted,
    );
    if (syncNow) {
      await _attemptSync();
    }
  }

  Future<void> flushPendingSync() async {
    await _attemptSync();
  }

  Future<void> saveDiagnosis(DiagnosisModel diagnosis) async {
    _error = null;
    await _upsertLocallyAndQueue(
      table: AppConstants.diagnosesTable,
      recordId: diagnosis.id,
      localData: diagnosis.toMap(),
      remoteData: _diagnosisRemoteMap(diagnosis),
    );
    await _attemptSync();
  }

  /// Recovers related records for a crop that was saved before its diagnosis
  /// rows were committed. The only source is the locally stored Add to My
  /// Crops suggestion card and local disease knowledge; this never calls AI.
  Future<bool> restoreCropDiagnosisFromLocalSuggestion({
    required CropModel crop,
    required List<ChatSessionModel> sessions,
    required Iterable<ChatMessageModel> messages,
  }) async {
    if (kIsWeb || sessions.isEmpty) return false;

    final sessionById = {
      for (final session in sessions)
        if (!session.isDeleted) session.id: session,
    };
    final suggestions = messages
        .where(
          (message) =>
              message.role == MessageRole.system &&
              message.userId == crop.userId &&
              sessionById[message.sessionId]?.userId == crop.userId &&
              message.metadata?['type'] == 'add_crop_suggestion',
        )
        .toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));

    for (final suggestion in suggestions) {
      final metadata = suggestion.metadata ?? const <String, dynamic>{};
      final diseaseName = (metadata['disease_name'] as String? ?? '').trim();
      if (diseaseName.isEmpty) continue;

      final cropTypeValue =
          (metadata['crop_type'] as String? ?? crop.cropType.value).trim();
      final cropType = CropType.values.firstWhere(
        (type) => type.value == cropTypeValue,
        orElse: () => crop.cropType,
      );
      if (cropType != crop.cropType) continue;

      final labelKey = (metadata['label_key'] as String? ?? '').trim();
      final knowledge = await _findLocalDiseaseKnowledge(
        cropType: cropType,
        diseaseName: diseaseName,
        labelKey: labelKey,
      );
      final existingRows = await _db.queryDiagnosesForCrop(crop.id);
      final requestedDiagnosisId =
          (metadata['diagnosis_id'] as String? ?? '').trim();
      DiagnosisModel? diagnosis;
      for (final row in existingRows) {
        final candidate = DiagnosisModel.fromMap(row);
        final sameStoredId = requestedDiagnosisId.isNotEmpty &&
            candidate.id == requestedDiagnosisId;
        final sameConversationDiagnosis =
            candidate.chatSessionId == suggestion.sessionId &&
                candidate.diseaseName.trim().toLowerCase() ==
                    diseaseName.toLowerCase();
        if (sameStoredId || sameConversationDiagnosis) {
          diagnosis = candidate;
          break;
        }
      }

      final now = DateTime.now();
      final diagnosedAt = DateTime.tryParse(
            metadata['diagnosed_at'] as String? ?? '',
          ) ??
          suggestion.createdAt;
      final writes = <LocalSyncUpsert>[];
      final rawRegions = metadata['detected_regions_json'];
      Map<String, dynamic>? detectedRegions;
      if (rawRegions is Map) {
        detectedRegions = Map<String, dynamic>.from(rawRegions);
      } else if (rawRegions is String && rawRegions.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawRegions);
          if (decoded is Map) {
            detectedRegions = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {
          // Keep the diagnosis while omitting malformed optional metadata.
        }
      }
      final rawConfidence = metadata['confidence_score'];
      final recoveredConfidence = rawConfidence is num
          ? rawConfidence.toDouble()
          : double.tryParse(rawConfidence?.toString() ?? '');
      final recoveredSummary =
          _nonEmptyText(metadata['summary']) ?? knowledge?.description;
      final existingDiagnosis = diagnosis;
      late final DiagnosisModel recoveredDiagnosis;
      if (existingDiagnosis == null) {
        var diagnosisId = requestedDiagnosisId.isNotEmpty
            ? requestedDiagnosisId
            : suggestion.id;
        final idCollision = await _db.queryById(
          AppConstants.diagnosesTable,
          diagnosisId,
        );
        if (idCollision != null) diagnosisId = const Uuid().v4();
        recoveredDiagnosis = DiagnosisModel(
          id: diagnosisId,
          cropId: crop.id,
          userId: crop.userId,
          chatSessionId: suggestion.sessionId,
          diagnosisMode: DiagnosisMode.values.firstWhere(
            (mode) =>
                mode.value ==
                (metadata['diagnosis_mode'] as String? ?? 'offline'),
            orElse: () => DiagnosisMode.offline,
          ),
          labelKey: labelKey.isEmpty ? null : labelKey,
          diseaseName: diseaseName,
          confidenceScore: recoveredConfidence,
          severity: Severity.values.firstWhere(
            (value) =>
                value.value == (metadata['severity'] as String? ?? 'moderate'),
            orElse: () => Severity.moderate,
          ),
          resultLabel: metadata['result_label'] as String?,
          summary: recoveredSummary,
          imageUrl: _nonEmptyText(metadata['image_url']),
          detectedRegionsJson: detectedRegions,
          videoUrl: _nonEmptyText(metadata['video_url']),
          modelName: _nonEmptyText(metadata['model_name']),
          modelVersion: _nonEmptyText(metadata['model_version']),
          diagnosedAt: diagnosedAt,
          createdAt: diagnosedAt,
          updatedAt: now,
        );
      } else {
        // Older saves may have created the diagnosis without some metadata.
        // Fill only missing fields; never replace an existing local value.
        recoveredDiagnosis = DiagnosisModel(
          id: existingDiagnosis.id,
          cropId: existingDiagnosis.cropId,
          userId: existingDiagnosis.userId,
          chatSessionId: _nonEmptyText(existingDiagnosis.chatSessionId) == null
              ? suggestion.sessionId
              : existingDiagnosis.chatSessionId,
          diagnosisMode: existingDiagnosis.diagnosisMode,
          labelKey: _nonEmptyText(existingDiagnosis.labelKey) ??
              (labelKey.isEmpty ? null : labelKey),
          diseaseName: existingDiagnosis.diseaseName,
          confidenceScore:
              existingDiagnosis.confidenceScore ?? recoveredConfidence,
          severity: existingDiagnosis.severity,
          resultLabel: _nonEmptyText(existingDiagnosis.resultLabel) ??
              _nonEmptyText(metadata['result_label']),
          summary: _nonEmptyText(existingDiagnosis.summary) ?? recoveredSummary,
          imageUrl: _nonEmptyText(existingDiagnosis.imageUrl) ??
              _nonEmptyText(metadata['image_url']),
          videoUrl: _nonEmptyText(existingDiagnosis.videoUrl) ??
              _nonEmptyText(metadata['video_url']),
          detectedRegionsJson:
              existingDiagnosis.detectedRegionsJson ?? detectedRegions,
          modelName: _nonEmptyText(existingDiagnosis.modelName) ??
              _nonEmptyText(metadata['model_name']),
          modelVersion: _nonEmptyText(existingDiagnosis.modelVersion) ??
              _nonEmptyText(metadata['model_version']),
          diagnosedAt: existingDiagnosis.diagnosedAt,
          syncVersion: existingDiagnosis.syncVersion,
          isDeleted: existingDiagnosis.isDeleted,
          createdAt: existingDiagnosis.createdAt,
          updatedAt: now,
        );
      }
      diagnosis = recoveredDiagnosis;
      var diagnosisChanged = existingDiagnosis == null;
      if (existingDiagnosis != null) {
        final before = existingDiagnosis.toMap();
        final after = recoveredDiagnosis.toMap();
        before['updated_at'] = after['updated_at'];
        diagnosisChanged = jsonEncode(before) != jsonEncode(after);
      }
      if (diagnosisChanged) {
        writes.add(
          LocalSyncUpsert(
            tableName: AppConstants.diagnosesTable,
            recordId: recoveredDiagnosis.id,
            localData: recoveredDiagnosis.toMap(),
            remoteData: _diagnosisRemoteMap(recoveredDiagnosis),
          ),
        );
      }

      final actionSteps = _stringList(metadata['recommended_actions']);
      final treatmentSteps = _normalizeTreatmentSteps(
        actionSteps.isNotEmpty
            ? actionSteps
            : [
                ...?knowledge?.treatmentSteps,
                ...?knowledge?.preventionSteps,
              ],
      );
      final existingTreatments = await _db.queryTreatmentsForCrop(crop.id);
      TreatmentModel? treatment;
      for (final row in existingTreatments) {
        final candidate = TreatmentModel.fromMap(row);
        if (candidate.diagnosisId == diagnosis.id) {
          treatment = candidate;
          break;
        }
      }

      if (treatment == null && treatmentSteps.isNotEmpty) {
        final plan = TreatmentPlanService.build(
          treatmentSteps: treatmentSteps,
          startDate: diagnosedAt,
          expectedDurationDays: knowledge?.estimatedRecoveryDays,
        );
        final treatmentId = const Uuid().v4();
        final healthy = diagnosis.severity == Severity.healthy ||
            diseaseName.toLowerCase().contains('healthy');
        treatment = TreatmentModel(
          id: treatmentId,
          cropId: crop.id,
          diagnosisId: diagnosis.id,
          userId: crop.userId,
          diseaseName: diseaseName,
          treatmentTitle: healthy
              ? 'Daily Care Plan — ${cropType.name[0].toUpperCase()}${cropType.name.substring(1)}'
              : 'Treatment Plan — $diseaseName',
          treatmentSteps: plan.sourceSteps,
          expectedDurationDays: plan.durationDays,
          status: TreatmentStatus.ongoing,
          startedAt: diagnosedAt,
          source: 'local-diagnosis',
          createdAt: now,
          updatedAt: now,
        );
        writes.add(
          LocalSyncUpsert(
            tableName: AppConstants.treatmentsTable,
            recordId: treatment.id,
            localData: treatment.toMap(),
            remoteData: _treatmentRemoteMap(treatment),
          ),
        );

        for (var index = 0; index < plan.tasks.length; index++) {
          final plannedTask = plan.tasks[index];
          final task = TreatmentTaskModel(
            id: const Uuid().v4(),
            treatmentId: treatment.id,
            cropId: crop.id,
            userId: crop.userId,
            title: plannedTask.title,
            description: plannedTask.description,
            dueAt: plannedTask.dueAt,
            status: TaskStatus.pending,
            taskOrder: index + 1,
            createdAt: now,
            updatedAt: now,
          );
          writes.add(
            LocalSyncUpsert(
              tableName: AppConstants.treatmentTasksTable,
              recordId: task.id,
              localData: task.toMap(),
              remoteData: _treatmentTaskRemoteMap(task),
            ),
          );
        }
      } else if (treatment != null) {
        final existingTasks = await _db.queryTasksForTreatment(treatment.id);
        if (existingTasks.isEmpty && treatment.treatmentSteps.isNotEmpty) {
          final plan = TreatmentPlanService.build(
            treatmentSteps: treatment.treatmentSteps,
            startDate: treatment.startedAt ?? diagnosedAt,
            expectedDurationDays: treatment.expectedDurationDays ??
                knowledge?.estimatedRecoveryDays,
          );
          for (var index = 0; index < plan.tasks.length; index++) {
            final plannedTask = plan.tasks[index];
            final task = TreatmentTaskModel(
              id: const Uuid().v4(),
              treatmentId: treatment.id,
              cropId: crop.id,
              userId: crop.userId,
              title: plannedTask.title,
              description: plannedTask.description,
              dueAt: plannedTask.dueAt,
              status: TaskStatus.pending,
              taskOrder: index + 1,
              createdAt: now,
              updatedAt: now,
            );
            writes.add(
              LocalSyncUpsert(
                tableName: AppConstants.treatmentTasksTable,
                recordId: task.id,
                localData: task.toMap(),
                remoteData: _treatmentTaskRemoteMap(task),
              ),
            );
          }
        }
      }

      if (writes.isEmpty) return false;
      await _upsertAllLocallyAndQueue(writes);
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<DiseaseKnowledgeModel?> _findLocalDiseaseKnowledge({
    required CropType cropType,
    required String diseaseName,
    required String labelKey,
  }) async {
    final cachedRows = await _db.queryDiseaseKnowledge(cropType.value);
    final cached = <DiseaseKnowledgeModel>[];
    for (final row in cachedRows) {
      try {
        cached.add(DiseaseKnowledgeModel.fromMap(row));
      } catch (_) {
        // A bad cached row must not prevent the bundled offline match.
      }
    }
    final candidates = [
      ...cached,
      ...BundledDiseaseKnowledge.records(cropType: cropType.value),
    ];
    final normalizedLabel = labelKey.trim().toLowerCase();
    final normalizedDisease = diseaseName.trim().toLowerCase();
    for (final candidate in candidates) {
      if (candidate.cropType != cropType) continue;
      if (normalizedLabel.isNotEmpty &&
          candidate.labelKey?.trim().toLowerCase() == normalizedLabel) {
        return candidate;
      }
    }
    for (final candidate in candidates) {
      if (candidate.cropType == cropType &&
          candidate.diseaseName.trim().toLowerCase() == normalizedDisease) {
        return candidate;
      }
    }
    return null;
  }

  String? _nonEmptyText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> completeTreatmentTimeline({
    required CropModel crop,
    required TreatmentModel treatment,
    required bool healed,
    String? completionNote,
  }) async {
    _error = null;
    final now = DateTime.now();
    final closedTreatment = treatment.copyWith(
      status: healed
          ? TreatmentStatus.completed
          : TreatmentStatus.needsReassessment,
      endedAt: now,
      reassessmentRequired: !healed,
      notes: _mergeNotes(treatment.notes, completionNote),
      updatedAt: now,
    );
    final archivedCrop = crop.copyWith(
      status: CropStatus.archived,
      lastCheckedAt: now,
      updatedAt: now,
    );

    await _upsertLocallyAndQueue(
      table: AppConstants.treatmentsTable,
      recordId: closedTreatment.id,
      localData: closedTreatment.toMap(),
      remoteData: _treatmentRemoteMap(closedTreatment),
    );
    await _upsertLocallyAndQueue(
      table: AppConstants.cropsTable,
      recordId: archivedCrop.id,
      localData: archivedCrop.toMap(),
      remoteData: _remoteMap(archivedCrop),
    );

    final cropIndex = _crops.indexWhere((candidate) => candidate.id == crop.id);
    if (cropIndex != -1) {
      _crops[cropIndex] = archivedCrop;
    }

    notifyListeners();
    await _attemptSync();
  }

  Future<TreatmentPlanRevisionResult?> reviseRemainingTreatmentPlan({
    required TreatmentModel treatment,
    required List<TreatmentTaskModel> tasks,
    required List<String> recommendedActions,
    required String assessment,
    required double healthScore,
    required DateTime assessedAt,
    required ProgressStatus progressStatus,
    required String checkInId,
  }) async {
    if (checkInId.trim().isEmpty ||
        _revisedPlanCheckInIds.contains(checkInId) ||
        !_planRevisionCheckInsInProgress.add(checkInId)) {
      return null;
    }

    try {
      final steps = _normalizeTreatmentSteps(recommendedActions);
      final tasksById = {for (final task in tasks) task.id: task};
      for (final row in await _db.queryAllTasksForCrop(treatment.cropId)) {
        final localTask = TreatmentTaskModel.fromMap(row);
        final existingTask = tasksById[localTask.id];
        if (existingTask == null ||
            localTask.updatedAt.isAfter(existingTask.updatedAt)) {
          tasksById[localTask.id] = localTask;
        }
      }

      final allTreatmentTasks = tasksById.values.toList(growable: false);
      final pendingTasks = allTreatmentTasks
          .where((task) =>
              task.treatmentId == treatment.id &&
              !task.isDeleted &&
              task.status == TaskStatus.pending)
          .toList()
        ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
      if (steps.isEmpty || pendingTasks.isEmpty) return null;

      _error = null;
      final now = DateTime.now();
      final assessedLocal = assessedAt.toLocal();
      final today = DateTime(
        assessedLocal.year,
        assessedLocal.month,
        assessedLocal.day,
      );
      final tomorrow = today.add(const Duration(days: 1));
      final planStart =
          DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9);
      final lastPendingDay = pendingTasks
          .map((task) => task.dueAt.toLocal())
          .map((date) => DateTime(date.year, date.month, date.day))
          .reduce((left, right) => left.isAfter(right) ? left : right);
      final remainingDays = math.max(
        1,
        lastPendingDay.difference(tomorrow).inDays + 1,
      );
      final durationDays =
          math.max(remainingDays, steps.length).clamp(1, 42).toInt();
      final plan = TreatmentPlanService.build(
        treatmentSteps: steps,
        startDate: planStart,
        expectedDurationDays: durationDays,
      );
      final revisedTreatment = treatment.copyWith(
        treatmentTitle: 'AI-updated Treatment Plan — ${treatment.diseaseName}',
        treatmentSteps: plan.sourceSteps,
        expectedDurationDays: plan.durationDays,
        status: TreatmentStatus.ongoing,
        reassessmentRequired: false,
        notes: _mergeNotes(
          treatment.notes,
          'AI revised the remaining treatment after a '
          '${progressStatus.value} check-in '
          '(${healthScore.toStringAsFixed(0)}% health). ${assessment.trim()}',
        ),
        source: 'ai-progress-reassessment',
        syncVersion: treatment.syncVersion + 1,
        startedAt: planStart,
        updatedAt: now,
      );
      await _upsertLocallyAndQueue(
        table: AppConstants.treatmentsTable,
        recordId: revisedTreatment.id,
        localData: revisedTreatment.toMap(),
        remoteData: _treatmentRemoteMap(revisedTreatment),
      );

      final completedCheckInDayTasks = <TreatmentTaskModel>[];
      final retiredTasks = <TreatmentTaskModel>[];
      for (final task in pendingTasks) {
        final dueLocal = task.dueAt.toLocal();
        final dueDay = DateTime(dueLocal.year, dueLocal.month, dueLocal.day);
        if (dueDay == today) {
          final completed = task.copyWith(
            status: TaskStatus.completed,
            completedAt: assessedAt,
            syncVersion: task.syncVersion + 1,
            updatedAt: now,
          );
          await _upsertLocallyAndQueue(
            table: AppConstants.treatmentTasksTable,
            recordId: completed.id,
            localData: completed.toMap(),
            remoteData: _treatmentTaskRemoteMap(completed),
          );
          completedCheckInDayTasks.add(completed);
          continue;
        }

        final retired = task.copyWith(
          isDeleted: true,
          syncVersion: task.syncVersion + 1,
          updatedAt: now,
        );
        await _upsertLocallyAndQueue(
          table: AppConstants.treatmentTasksTable,
          recordId: retired.id,
          localData: retired.toMap(),
          remoteData: _treatmentTaskRemoteMap(retired),
        );
        retiredTasks.add(retired);
      }

      final replacementTasks = <TreatmentTaskModel>[];
      for (var index = 0; index < plan.tasks.length; index++) {
        final plannedTask = plan.tasks[index];
        final task = TreatmentTaskModel(
          id: const Uuid().v4(),
          treatmentId: treatment.id,
          cropId: treatment.cropId,
          userId: treatment.userId,
          title: plannedTask.title,
          description: plannedTask.description,
          dueAt: plannedTask.dueAt,
          status: TaskStatus.pending,
          taskOrder: index + 1,
          createdAt: now,
          updatedAt: now,
        );
        await _upsertLocallyAndQueue(
          table: AppConstants.treatmentTasksTable,
          recordId: task.id,
          localData: task.toMap(),
          remoteData: _treatmentTaskRemoteMap(task),
        );
        replacementTasks.add(task);
      }

      final checkInDayTaskIds =
          completedCheckInDayTasks.map((task) => task.id).toSet();
      final retainedTasks = allTreatmentTasks
          .where((task) =>
              task.treatmentId != treatment.id ||
              task.isDeleted ||
              task.status == TaskStatus.completed ||
              checkInDayTaskIds.contains(task.id))
          .map((task) => checkInDayTaskIds.contains(task.id)
              ? completedCheckInDayTasks
                  .firstWhere((completed) => completed.id == task.id)
              : task);
      final revisedTasks = [
        ...retainedTasks,
        ...replacementTasks,
      ]..sort((a, b) {
          final dueCompare = a.dueAt.compareTo(b.dueAt);
          if (dueCompare != 0) return dueCompare;
          return (a.taskOrder ?? 0).compareTo(b.taskOrder ?? 0);
        });

      notifyListeners();
      await _attemptSync();
      _revisedPlanCheckInIds.add(checkInId);
      return TreatmentPlanRevisionResult(
        treatment: revisedTreatment,
        tasks: revisedTasks,
        retiredTasks: retiredTasks,
      );
    } finally {
      _planRevisionCheckInsInProgress.remove(checkInId);
    }
  }

  Future<TreatmentExtensionResult?> extendTreatmentTracking({
    required CropModel crop,
    required TreatmentModel currentTreatment,
    required List<String> treatmentSteps,
    required String explanation,
    List<String> sources = const [],
  }) async {
    final cleanedSteps = _normalizeTreatmentSteps(treatmentSteps);
    if (cleanedSteps.isEmpty) {
      return null;
    }

    _error = null;
    final now = DateTime.now();
    final timelineStart = DateTime(now.year, now.month, now.day);
    final plan = TreatmentPlanService.build(
      treatmentSteps: cleanedSteps,
      startDate: timelineStart,
      expectedDurationDays: math.max(cleanedSteps.length, 7),
    );
    final reassessmentNote = _mergeNotes(
      explanation,
      sources.isEmpty
          ? null
          : 'Sources:\n${sources.map((source) => '- $source').join('\n')}',
    );

    final closedTreatment = currentTreatment.copyWith(
      status: TreatmentStatus.needsReassessment,
      endedAt: now,
      reassessmentRequired: true,
      notes: _mergeNotes(currentTreatment.notes, reassessmentNote),
      updatedAt: now,
    );

    await _upsertLocallyAndQueue(
      table: AppConstants.treatmentsTable,
      recordId: closedTreatment.id,
      localData: closedTreatment.toMap(),
      remoteData: _treatmentRemoteMap(closedTreatment),
    );

    final extendedTreatment = TreatmentModel(
      id: const Uuid().v4(),
      cropId: crop.id,
      diagnosisId: currentTreatment.diagnosisId,
      userId: crop.userId,
      diseaseName: currentTreatment.diseaseName,
      treatmentTitle: 'Extended Treatment — ${currentTreatment.diseaseName}',
      treatmentSteps: plan.sourceSteps,
      expectedDurationDays: plan.durationDays,
      status: TreatmentStatus.ongoing,
      startedAt: timelineStart,
      notes: reassessmentNote,
      source: 'ai-reassessment',
      createdAt: now,
      updatedAt: now,
    );

    await _upsertLocallyAndQueue(
      table: AppConstants.treatmentsTable,
      recordId: extendedTreatment.id,
      localData: extendedTreatment.toMap(),
      remoteData: _treatmentRemoteMap(extendedTreatment),
    );

    final newTasks = <TreatmentTaskModel>[];
    for (var index = 0; index < plan.tasks.length; index++) {
      final plannedTask = plan.tasks[index];
      final task = TreatmentTaskModel(
        id: const Uuid().v4(),
        treatmentId: extendedTreatment.id,
        cropId: crop.id,
        userId: crop.userId,
        title: plannedTask.title,
        description: plannedTask.description,
        dueAt: plannedTask.dueAt,
        status: TaskStatus.pending,
        taskOrder: index + 1,
        createdAt: now,
        updatedAt: now,
      );
      newTasks.add(task);
      await _upsertLocallyAndQueue(
        table: AppConstants.treatmentTasksTable,
        recordId: task.id,
        localData: task.toMap(),
        remoteData: _treatmentTaskRemoteMap(task),
      );
    }

    final updatedCrop = crop.copyWith(
      status: CropStatus.recovering,
      lastCheckedAt: now,
      updatedAt: now,
    );

    await _upsertLocallyAndQueue(
      table: AppConstants.cropsTable,
      recordId: updatedCrop.id,
      localData: updatedCrop.toMap(),
      remoteData: _remoteMap(updatedCrop),
    );

    final cropIndex = _crops.indexWhere((candidate) => candidate.id == crop.id);
    if (cropIndex != -1) {
      _crops[cropIndex] = updatedCrop;
    }

    notifyListeners();
    await _attemptSync();

    return TreatmentExtensionResult(
      crop: updatedCrop,
      previousTreatment: closedTreatment,
      treatment: extendedTreatment,
      tasks: newTasks,
    );
  }

  /// Recomputes [latestHealthScore] for [cropId] from the local DB without
  /// requiring a photo check-in. Used so marking a treatment task DONE in the
  /// dashboard or notifications screen immediately moves Farm Vitality.
  ///
  /// Silent on missing crop / DB failure — best-effort UI sync.
  Future<void> recomputeHealthScoreForCrop(String cropId) async {
    if (cropId.isEmpty) return;
    final idx = _crops.indexWhere((c) => c.id == cropId);
    if (idx == -1) return;

    try {
      final taskRows = await _db.queryTasksForCrop(cropId);
      final tasks = taskRows.map(TreatmentTaskModel.fromMap).toList();

      final dxRows = await _db.queryDiagnosesForCrop(cropId);
      final diagnoses = dxRows.map(DiagnosisModel.fromMap).toList();

      final snapshot = HealthScoreService.computeScoreAndStatus(
        tasks: tasks,
        diagnoses: diagnoses,
        previousScore: _crops[idx].latestHealthScore,
        now: DateTime.now(),
      );

      await updateCropHealthScore(
        cropId,
        snapshot.score.toDouble(),
        snapshot.status,
      );
    } catch (_) {
      // Best-effort; leave the existing score untouched.
    }
  }

  List<String> _normalizeTreatmentSteps(List<String> treatmentSteps) {
    return TreatmentActionParser.normalize(treatmentSteps);
  }

  int? _expectedDurationFor({
    required String labelKey,
    required CropType cropType,
  }) {
    final normalizedLabel = labelKey.trim().toLowerCase();
    final candidates = [
      ..._diseaseKnowledge,
      ...BundledDiseaseKnowledge.records(cropType: cropType.value),
    ];
    for (final knowledge in candidates) {
      if (knowledge.labelKey?.toLowerCase() == normalizedLabel) {
        return knowledge.estimatedRecoveryDays;
      }
    }
    return null;
  }

  Future<List<DiseaseTreatmentDayStepModel>> _loadLocalTreatmentProtocol(
    String diseaseKnowledgeBaseId,
  ) async {
    final rows =
        await _db.queryDiseaseTreatmentDaySteps(diseaseKnowledgeBaseId);
    final steps = <DiseaseTreatmentDayStepModel>[];
    for (final row in rows) {
      try {
        steps.add(DiseaseTreatmentDayStepModel.fromMap(row));
      } catch (_) {
        // Ignore malformed cached rows and keep the available disease guidance.
      }
    }
    return steps;
  }

  String? _mergeNotes(String? existing, String? addition) {
    final current = existing?.trim() ?? '';
    final next = addition?.trim() ?? '';
    if (current.isEmpty) {
      return next.isEmpty ? null : next;
    }
    if (next.isEmpty || current.contains(next)) {
      return current;
    }
    return '$current\n\n$next';
  }

  Future<List<DiseaseKnowledgeModel>> fetchDiseaseKnowledge(
      {String? cropType}) async {
    final cachedRows = await _db.queryDiseaseKnowledge(cropType ?? '');
    final cachedKnowledge = <DiseaseKnowledgeModel>[];
    for (final row in cachedRows) {
      try {
        cachedKnowledge.add(DiseaseKnowledgeModel.fromMap(row));
      } catch (_) {
        // Keep usable cached entries and continue with bundled knowledge.
      }
    }

    final bundledAll = BundledDiseaseKnowledge.records();
    final cachedIds = cachedKnowledge.map((item) => item.id).toSet();
    final bundledToCache = bundledAll
        .where((item) => !cachedIds.contains(item.id))
        .toList(growable: false);
    if (bundledToCache.isNotEmpty) {
      await _db.upsertRows(
        AppConstants.diseaseKnowledgeTable,
        bundledToCache.map((knowledge) => knowledge.toMap()),
      );
    }

    _mergeDiseaseKnowledge([...bundledAll, ...cachedKnowledge]);
    notifyListeners();
    unawaited(_refreshDiseaseKnowledge(cropType: cropType));

    return cropType == null || cropType.trim().isEmpty
        ? _diseaseKnowledge
        : _diseaseKnowledge
            .where((knowledge) => knowledge.cropType.value == cropType)
            .toList(growable: false);
  }

  Future<void> _refreshDiseaseKnowledge({String? cropType}) async {
    try {
      final rows = await _supabase.getDiseaseKnowledge(cropType: cropType);
      if (rows.isEmpty) return;
      final remoteKnowledge =
          rows.map(DiseaseKnowledgeModel.fromMap).toList(growable: false);
      await _db.upsertRows(
        AppConstants.diseaseKnowledgeTable,
        remoteKnowledge.map((knowledge) => knowledge.toMap()),
      );
      _mergeDiseaseKnowledge(remoteKnowledge);
      notifyListeners();
    } catch (_) {
      // Knowledge already came from SQLite or the bundled offline catalog.
    }
  }

  Future<DiseaseDatasetImportSummary> importDiseaseKnowledgeDataset({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final rows = _decodeDatasetRows(bytes: bytes, fileName: fileName);
    final imported = <DiseaseKnowledgeModel>[];
    final warnings = <String>[];

    for (var index = 0; index < rows.length; index++) {
      try {
        imported.add(_mapDiseaseKnowledgeRow(rows[index]));
      } catch (error) {
        warnings.add('Row ${index + 1}: $error');
      }
    }

    final dedupedById = <String, DiseaseKnowledgeModel>{};
    for (final knowledge in imported) {
      dedupedById[knowledge.id] = knowledge;
    }

    final deduped = dedupedById.values.toList()
      ..sort((a, b) {
        final cropCompare = a.cropType.value.compareTo(b.cropType.value);
        if (cropCompare != 0) return cropCompare;
        return a.diseaseName
            .toLowerCase()
            .compareTo(b.diseaseName.toLowerCase());
      });

    if (deduped.isEmpty) {
      throw const FormatException(
        'No valid dataset rows found. Include at least crop_type and disease_name columns.',
      );
    }

    if (deduped.length != imported.length) {
      warnings.add(
        '${imported.length - deduped.length} duplicate row(s) were merged by ID before import.',
      );
    }

    final payload = deduped.map((knowledge) => knowledge.toMap()).toList();
    await _supabase.upsertDiseaseKnowledgeBatch(payload);
    await _db.upsertRows(AppConstants.diseaseKnowledgeTable, payload);

    _mergeDiseaseKnowledge(deduped);
    notifyListeners();

    return DiseaseDatasetImportSummary(
      fileName: fileName,
      totalRows: rows.length,
      importedRows: deduped.length,
      skippedRows: rows.length - imported.length,
      warnings: warnings,
    );
  }

  void _mergeDiseaseKnowledge(List<DiseaseKnowledgeModel> incoming) {
    final merged = <String, DiseaseKnowledgeModel>{
      for (final knowledge in _diseaseKnowledge) knowledge.id: knowledge,
    };

    for (final knowledge in incoming) {
      merged[knowledge.id] = knowledge;
    }

    _diseaseKnowledge = merged.values.toList()
      ..sort((a, b) {
        final cropCompare = a.cropType.value.compareTo(b.cropType.value);
        if (cropCompare != 0) return cropCompare;
        return a.diseaseName
            .toLowerCase()
            .compareTo(b.diseaseName.toLowerCase());
      });
  }

  List<Map<String, dynamic>> _decodeDatasetRows({
    required Uint8List bytes,
    required String fileName,
  }) {
    final normalizedFileName = fileName.toLowerCase();
    final content = utf8.decode(bytes);

    if (normalizedFileName.endsWith('.json')) {
      return _decodeJsonRows(content);
    }
    if (normalizedFileName.endsWith('.csv')) {
      return _decodeCsvRows(content);
    }

    throw const FormatException(
        'Unsupported file type. Choose a JSON or CSV file.');
  }

  List<Map<String, dynamic>> _decodeJsonRows(String content) {
    final decoded = jsonDecode(content);

    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }

    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      for (final key in const ['data', 'items', 'rows']) {
        final value = map[key];
        if (value is List) {
          return value
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
        }
      }

      return [map];
    }

    throw const FormatException(
      'JSON dataset must be a list of objects or an object containing a data/items list.',
    );
  }

  List<Map<String, dynamic>> _decodeCsvRows(String content) {
    final rows =
        const CsvToListConverter(shouldParseNumbers: false).convert(content);
    if (rows.isEmpty) return const [];

    final headers = rows.first
        .map((cell) => _normalizeKey(cell?.toString() ?? ''))
        .toList(growable: false);

    final mappedRows = <Map<String, dynamic>>[];
    for (final row in rows.skip(1)) {
      final isEmpty = row.every(
        (cell) => cell == null || cell.toString().trim().isEmpty,
      );
      if (isEmpty) continue;

      final mapped = <String, dynamic>{};
      for (var index = 0; index < headers.length; index++) {
        final header = headers[index];
        if (header.isEmpty) continue;
        mapped[header] = index < row.length ? row[index] : null;
      }
      mappedRows.add(mapped);
    }

    return mappedRows;
  }

  DiseaseKnowledgeModel _mapDiseaseKnowledgeRow(Map<String, dynamic> row) {
    final normalized = <String, dynamic>{};
    row.forEach((key, value) {
      normalized[_normalizeKey(key)] = value;
    });

    final cropType = _parseCropType(
      _requiredString(normalized, const ['crop_type', 'crop']),
    );
    final diseaseName = _requiredString(
      normalized,
      const ['disease_name', 'disease', 'name'],
    );
    final scientificName = _optionalString(
      normalized,
      const ['scientific_name'],
    );
    final createdAt = _parseDateTime(
          _valueForKeys(normalized, const ['created_at']),
        ) ??
        DateTime.now();
    final updatedAt =
        _parseDateTime(_valueForKeys(normalized, const ['updated_at'])) ??
            createdAt;

    return DiseaseKnowledgeModel(
      id: _optionalString(normalized, const ['id']) ??
          _buildStableKnowledgeId(cropType, diseaseName, scientificName),
      cropType: cropType,
      labelKey: _optionalString(
            normalized,
            const ['label_key', 'labelkey', 'class_key', 'taxonomy_key'],
          ) ??
          _buildStableLabelKey(cropType, diseaseName),
      diseaseName: diseaseName,
      scientificName: scientificName,
      description:
          _optionalString(normalized, const ['description', 'summary']),
      symptoms: _parseStringList(_valueForKeys(normalized, const ['symptoms'])),
      causes: _parseStringList(_valueForKeys(normalized, const ['causes'])),
      treatmentSteps: _parseStringList(
        _valueForKeys(
            normalized, const ['treatment_steps', 'treatments', 'treatment']),
      ),
      preventionSteps: _parseStringList(
        _valueForKeys(normalized, const ['prevention_steps', 'prevention']),
      ),
      estimatedRecoveryDays: _parseInt(
        _valueForKeys(
            normalized, const ['estimated_recovery_days', 'recovery_days']),
      ),
      severityNotes: _optionalString(normalized, const ['severity_notes']),
      cautionNotes: _optionalString(
        normalized,
        const ['caution_notes', 'cautions'],
      ),
      isActive: _parseBool(
        _valueForKeys(normalized, const ['is_active', 'active']),
        defaultValue: true,
      ),
      sourceName: _optionalString(normalized, const ['source_name', 'source']),
      sourceUrl: _optionalString(normalized, const ['source_url']),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  dynamic _valueForKeys(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final normalizedKey = _normalizeKey(key);
      if (row.containsKey(normalizedKey)) {
        return row[normalizedKey];
      }
    }
    return null;
  }

  String _requiredString(Map<String, dynamic> row, List<String> keys) {
    final value = _optionalString(row, keys);
    if (value == null || value.isEmpty) {
      throw FormatException('Missing required field: ${keys.first}');
    }
    return value;
  }

  String? _optionalString(Map<String, dynamic> row, List<String> keys) {
    final value = _valueForKeys(row, keys);
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  List<String>? _parseStringList(dynamic raw) {
    if (raw == null) return null;
    if (raw is List) {
      final items = raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
      return items.isEmpty ? null : items;
    }

    final text = raw.toString().trim();
    if (text.isEmpty) return null;

    if (text.startsWith('[') && text.endsWith(']')) {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        final items = decoded
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
        return items.isEmpty ? null : items;
      }
    }

    final items = text
        .split(RegExp(r'\r?\n|;|\|'))
        .expand((segment) => segment.split(','))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    return items.isEmpty ? null : items;
  }

  int? _parseInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toInt();
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  bool _parseBool(dynamic raw, {required bool defaultValue}) {
    if (raw == null) return defaultValue;
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;

    final normalized = raw.toString().trim().toLowerCase();
    if (normalized.isEmpty) return defaultValue;
    if (const ['true', '1', 'yes', 'y', 'active'].contains(normalized)) {
      return true;
    }
    if (const ['false', '0', 'no', 'n', 'inactive'].contains(normalized)) {
      return false;
    }
    return defaultValue;
  }

  DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  CropType _parseCropType(String raw) {
    final normalized = _normalizeKey(raw).replaceAll('_', '');
    switch (normalized) {
      case 'tomato':
        return CropType.tomato;
      case 'pechay':
      case 'bokchoy':
      case 'bokchoi':
        return CropType.pechay;
      case 'pepper':
      case 'bellpepper':
      case 'chilipepper':
        return CropType.pepper;
      case 'eggplant':
      case 'aubergine':
        return CropType.eggplant;
      case 'squash':
        return CropType.squash;
      default:
        throw FormatException('Unsupported crop_type value: $raw');
    }
  }

  String _normalizeKey(String key) {
    final trimmed = key.replaceAll('\ufeff', '').trim();
    final withSnakeCase = trimmed.replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (match) => '${match.group(1)}_${match.group(2)}',
    );
    return withSnakeCase
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '')
        .toLowerCase();
  }

  String _buildStableKnowledgeId(
    CropType cropType,
    String diseaseName,
    String? scientificName,
  ) {
    final diseaseSlug = _normalizeKey(diseaseName);
    final scientificSlug =
        scientificName == null || scientificName.trim().isEmpty
            ? ''
            : '_${_normalizeKey(scientificName)}';
    return '${cropType.value}_$diseaseSlug$scientificSlug';
  }

  String _buildStableLabelKey(CropType cropType, String diseaseName) {
    return '${cropType.value}_${_normalizeKey(diseaseName)}';
  }
}

class TreatmentTimelineRebaseResult {
  final TreatmentModel treatment;
  final List<TreatmentTaskModel> tasks;

  const TreatmentTimelineRebaseResult({
    required this.treatment,
    required this.tasks,
  });
}

class TreatmentExtensionResult {
  final CropModel crop;
  final TreatmentModel previousTreatment;
  final TreatmentModel treatment;
  final List<TreatmentTaskModel> tasks;

  const TreatmentExtensionResult({
    required this.crop,
    required this.previousTreatment,
    required this.treatment,
    required this.tasks,
  });
}

class TreatmentPlanRevisionResult {
  final TreatmentModel treatment;
  final List<TreatmentTaskModel> tasks;
  final List<TreatmentTaskModel> retiredTasks;

  const TreatmentPlanRevisionResult({
    required this.treatment,
    required this.tasks,
    required this.retiredTasks,
  });
}

class DiseaseDatasetImportSummary {
  final String fileName;
  final int totalRows;
  final int importedRows;
  final int skippedRows;
  final List<String> warnings;

  const DiseaseDatasetImportSummary({
    required this.fileName,
    required this.totalRows,
    required this.importedRows,
    required this.skippedRows,
    this.warnings = const [],
  });
}
