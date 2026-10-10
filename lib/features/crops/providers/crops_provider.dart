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
import '../../../data/models/diagnosis_model.dart';
import '../../../data/models/disease_knowledge_model.dart';
import '../../../data/models/disease_treatment_day_step_model.dart';
import '../../../data/models/progress_update_model.dart';
import '../../../data/models/treatment_model.dart';
import '../../../data/models/treatment_task_model.dart';
import '../../../data/remote/supabase_service.dart';
import '../../../services/health_score_service.dart';
import '../../../services/sync_service.dart';
import '../../../services/treatment_plan_service.dart';

class CropsProvider extends ChangeNotifier {
  final SupabaseService _supabase;
  final DatabaseHelper _db;
  final SyncService _sync;

  List<CropModel> _crops = [];
  List<DiseaseKnowledgeModel> _diseaseKnowledge = [];
  bool _isLoading = false;
  String? _error;

  CropsProvider({
    required SupabaseService supabase,
    required DatabaseHelper db,
    required SyncService sync,
  })  : _supabase = supabase,
        _db = db,
        _sync = sync;

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
      if (visibleLocalRows.isNotEmpty) {
        _crops = visibleLocalRows.map(CropModel.fromMap).toList();
        notifyListeners();
      }

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
        // Upsert remote only when it is at least as new as the local copy.
        final remoteDate = DateTime.tryParse(remoteUpdatedAt);
        final localDate = DateTime.tryParse(localUpdatedAt);
        if (remoteDate != null && localDate != null) {
          return !remoteDate.isBefore(localDate);
        }
        return remoteUpdatedAt.compareTo(localUpdatedAt) >= 0;
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
      await _sync.queueSoftDelete(tableName: table, recordId: id);
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
      await _db.hardDelete(table, id);
      await _sync.queueDelete(tableName: table, recordId: id);
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
  }) async {
    if (kIsWeb) {
      await _supabase.upsertRecord(table: table, data: remoteData);
      return;
    }

    await _db.upsertRow(table, localData);
    await _sync.queueUpsert(
      tableName: table,
      recordId: recordId,
      data: remoteData,
    );
  }

  Future<void> _attemptSync() async {
    if (!_supabase.isSignedIn) {
      return;
    }
    try {
      await _sync.syncAll();
    } catch (_) {
      // Local state is already committed; the queue will retry later.
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
    DiagnosisMode diagnosisMode = DiagnosisMode.online,
    String? chatSessionId,
    String? locationLabel,
    String? notes,
    DateTime? plantedAt,
  }) async {
    try {
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

      await _upsertLocallyAndQueue(
        table: AppConstants.cropsTable,
        recordId: crop.id,
        localData: crop.toMap(),
        remoteData: _remoteMap(crop),
      );
      _crops.insert(0, crop);

      final normalizedDiseaseName = diseaseName.trim().isEmpty
          ? '${cropType.name[0].toUpperCase()}${cropType.name.substring(1)} condition'
          : diseaseName.trim();
      final diagnosis = DiagnosisModel(
        id: const Uuid().v4(),
        cropId: cropId,
        userId: userId,
        chatSessionId: chatSessionId,
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
        modelName: modelName,
        modelVersion: modelVersion,
        diagnosedAt: now,
        createdAt: now,
        updatedAt: now,
      );

      await _upsertLocallyAndQueue(
        table: AppConstants.diagnosesTable,
        recordId: diagnosis.id,
        localData: diagnosis.toMap(),
        remoteData: _diagnosisRemoteMap(diagnosis),
      );

      final normalizedTreatmentSteps = _normalizeTreatmentSteps(treatmentSteps);
      final knowledge = await _findDiseaseKnowledgeForDiagnosis(
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
          : await _loadTreatmentProtocol(knowledge.id);
      final usesReviewedProtocol = TreatmentPlanService.coversExpectedDuration(
        daySteps: protocolSteps,
        expectedDurationDays: expectedDurationDays,
      );

      // Create treatment
      if (normalizedTreatmentSteps.isNotEmpty || usesReviewedProtocol) {
        final treatmentId = const Uuid().v4();
        final plan = usesReviewedProtocol
            ? TreatmentPlanService.buildFromDaySteps(
                daySteps: protocolSteps,
                startDate: now,
                expectedDurationDays: expectedDurationDays,
              )
            : TreatmentPlanService.build(
                treatmentSteps: normalizedTreatmentSteps,
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

        await _upsertLocallyAndQueue(
          table: AppConstants.treatmentsTable,
          recordId: treatment.id,
          localData: treatment.toMap(),
          remoteData: _treatmentRemoteMap(treatment),
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
          await _upsertLocallyAndQueue(
            table: AppConstants.treatmentTasksTable,
            recordId: task.id,
            localData: task.toMap(),
            remoteData: _treatmentTaskRemoteMap(task),
          );
        }
      }

      notifyListeners();
      await _attemptSync();
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

  Future<void> saveProgressUpdate(
    ProgressUpdateModel update, {
    bool syncNow = true,
  }) async {
    _error = null;
    await _upsertLocallyAndQueue(
      table: AppConstants.progressUpdatesTable,
      recordId: update.id,
      localData: update.toMap(),
      remoteData: update.toMap()..['is_deleted'] = update.isDeleted,
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
    final normalized = <String>[];
    for (final step in treatmentSteps) {
      final trimmed = step.trim();
      if (trimmed.isEmpty || normalized.contains(trimmed)) {
        continue;
      }
      normalized.add(trimmed);
    }
    return normalized;
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

  Future<List<DiseaseTreatmentDayStepModel>> _loadTreatmentProtocol(
    String diseaseKnowledgeBaseId,
  ) async {
    try {
      final remoteRows =
          await _supabase.getDiseaseTreatmentDaySteps(diseaseKnowledgeBaseId);
      if (remoteRows.isNotEmpty) {
        final steps =
            remoteRows.map(DiseaseTreatmentDayStepModel.fromMap).toList();
        await _db.upsertRows(
          AppConstants.diseaseTreatmentDayStepsTable,
          steps.map((step) => step.toMap()),
        );
        return steps;
      }
    } catch (_) {}

    final cachedRows =
        await _db.queryDiseaseTreatmentDaySteps(diseaseKnowledgeBaseId);
    return cachedRows.map(DiseaseTreatmentDayStepModel.fromMap).toList();
  }

  Future<DiseaseKnowledgeModel?> _findDiseaseKnowledgeForDiagnosis({
    required CropType cropType,
    required String diseaseName,
    required String labelKey,
  }) async {
    if (_diseaseKnowledge.isEmpty) {
      await fetchDiseaseKnowledge(cropType: cropType.value);
    }

    final requestedLabel = labelKey.trim().toLowerCase();
    final requestedDisease = diseaseName.trim().toLowerCase();
    final normalizedLabel = _knowledgeComparisonKey(labelKey, cropType);
    final normalizedDisease = _knowledgeComparisonKey(diseaseName, cropType);

    for (final knowledge in _diseaseKnowledge) {
      if (knowledge.cropType != cropType) continue;
      if (requestedLabel.isNotEmpty &&
          (knowledge.labelKey?.trim().toLowerCase() == requestedLabel ||
              knowledge.diseaseName.trim().toLowerCase() == requestedLabel)) {
        return knowledge;
      }
    }

    for (final knowledge in _diseaseKnowledge) {
      if (knowledge.cropType == cropType &&
          requestedDisease.isNotEmpty &&
          knowledge.diseaseName.trim().toLowerCase() == requestedDisease) {
        return knowledge;
      }
    }

    for (final knowledge in _diseaseKnowledge) {
      if (knowledge.cropType != cropType) continue;
      final knowledgeLabel =
          _knowledgeComparisonKey(knowledge.labelKey ?? '', cropType);
      final knowledgeDisease =
          _knowledgeComparisonKey(knowledge.diseaseName, cropType);
      if (normalizedLabel.isNotEmpty && normalizedLabel == knowledgeLabel) {
        return knowledge;
      }
      if (normalizedDisease.isNotEmpty &&
          normalizedDisease == knowledgeDisease) {
        return knowledge;
      }
    }
    return null;
  }

  String _knowledgeComparisonKey(String value, CropType cropType) {
    var normalized = value.trim().toLowerCase();
    normalized = normalized.replaceFirst('${cropType.value}_', '');
    normalized = normalized.replaceFirst('${cropType.value} ', '');
    return normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '');
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
    try {
      final rows = await _supabase.getDiseaseKnowledge(cropType: cropType);
      if (rows.isNotEmpty) {
        _diseaseKnowledge = rows.map(DiseaseKnowledgeModel.fromMap).toList();
        await _db.upsertRows(
          AppConstants.diseaseKnowledgeTable,
          _diseaseKnowledge.map((knowledge) => knowledge.toMap()),
        );
        notifyListeners();
        return _diseaseKnowledge;
      }
    } catch (_) {}

    final cachedRows = await _db.queryDiseaseKnowledge(cropType ?? '');
    if (cachedRows.isNotEmpty) {
      _diseaseKnowledge =
          cachedRows.map(DiseaseKnowledgeModel.fromMap).toList();
      notifyListeners();
      return _diseaseKnowledge;
    }

    final bundledAll = BundledDiseaseKnowledge.records();
    if (bundledAll.isNotEmpty) {
      await _db.upsertRows(
        AppConstants.diseaseKnowledgeTable,
        bundledAll.map((knowledge) => knowledge.toMap()),
      );
    }
    _diseaseKnowledge = BundledDiseaseKnowledge.records(cropType: cropType);
    notifyListeners();
    return _diseaseKnowledge;
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
