import 'dart:convert';
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
import '../../../data/models/treatment_model.dart';
import '../../../data/models/treatment_task_model.dart';
import '../../../data/remote/supabase_service.dart';
import '../../../services/health_score_service.dart';

class CropsProvider extends ChangeNotifier {
  final SupabaseService _supabase;
  final DatabaseHelper _db;

  List<CropModel> _crops = [];
  List<DiseaseKnowledgeModel> _diseaseKnowledge = [];
  bool _isLoading = false;
  String? _error;

  CropsProvider({required SupabaseService supabase, required DatabaseHelper db})
      : _supabase = supabase,
        _db = db;

  List<CropModel> get crops => _crops;
  List<DiseaseKnowledgeModel> get diseaseKnowledge => _diseaseKnowledge;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<CropModel> get activeCrops => _crops
      .where((c) => c.status != CropStatus.archived && !c.isDeleted)
      .toList();

  // ─── Fetch ────────────────────────────────────────────────────────────────

  Future<void> fetchCrops(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Try remote first
      final rows = await _supabase.getCrops(userId);
      _crops = rows.map(CropModel.fromMap).toList();
      await _db.upsertRows(
        AppConstants.cropsTable,
        _crops.map((crop) => crop.toMap()),
      );
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

      await _supabase.upsertCrop(_remoteMap(crop));
      await _db.upsertRow(AppConstants.cropsTable, crop.toMap());
      _crops.insert(0, crop);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ─── Update ───────────────────────────────────────────────────────────────

  Future<bool> updateCrop(CropModel crop) async {
    try {
      final updated = crop.copyWith(updatedAt: DateTime.now());
      await _supabase.upsertCrop(_remoteMap(updated));
      await _db.upsertRow(AppConstants.cropsTable, updated.toMap());
      final idx = _crops.indexWhere((c) => c.id == updated.id);
      if (idx != -1) _crops[idx] = updated;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ─── Delete ───────────────────────────────────────────────────────────────

  Future<bool> deleteCrop(String cropId) async {
    try {
      final crop = _crops.cast<CropModel?>().firstWhere(
            (item) => item?.id == cropId,
            orElse: () => null,
          );
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

      if (crop != null) {
        try {
          final remoteDiagnosisRows = await _supabase.getDiagnosesByCrop(cropId);
          final remoteTreatmentRows = await _supabase.getTreatmentsByCrop(cropId);
          final remoteProgressRows = await _supabase.getProgressUpdates(cropId);
          final remoteTaskRows = (await _supabase.getTreatmentTasksByUser(crop.userId))
              .where((row) => row['crop_id'] == cropId)
              .toList(growable: false);
          final remoteNotificationIds = (await _supabase.getNotifications(crop.userId))
              .where((row) => row['crop_id'] == cropId)
              .map((row) => row['id'] as String?)
              .whereType<String>()
              .toList(growable: false);
          final remoteSessionRows = await _supabase.getChatSessionsByCrop(cropId);
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

          await _softDeleteRemoteRows(AppConstants.diagnosesTable, remoteDiagnosisRows);
          await _softDeleteRemoteRows(AppConstants.treatmentsTable, remoteTreatmentRows);
          await _softDeleteRemoteRows(AppConstants.treatmentTasksTable, remoteTaskRows);
          await _softDeleteRemoteRows(AppConstants.progressUpdatesTable, remoteProgressRows);
          await _softDeleteRemoteRows(AppConstants.chatSessionsTable, remoteSessionRows);
          await _hardDeleteRemoteRows(AppConstants.notificationsTable, remoteNotificationIds);
          await _hardDeleteRemoteRows(AppConstants.chatMessagesTable, remoteChatMessageIds);
        } catch (_) {
          // Best-effort remote cascade. Local deletion still proceeds.
        }
      }

      await _softDeleteLocalRows(AppConstants.diagnosesTable, diagnosisRows);
      await _softDeleteLocalRows(AppConstants.treatmentsTable, treatmentRows);
      await _softDeleteLocalRows(AppConstants.treatmentTasksTable, taskRows);
      await _softDeleteLocalRows(AppConstants.progressUpdatesTable, progressRows);
      await _softDeleteLocalRows(AppConstants.chatSessionsTable, sessionRows);
      await _hardDeleteLocalRows(
        AppConstants.notificationsTable,
        notificationRows
            .map((row) => row['id'] as String?)
            .whereType<String>(),
      );
      await _hardDeleteLocalRows(AppConstants.chatMessagesTable, chatMessageIds);

      await _supabase.softDeleteCrop(cropId);
      await _db.softDelete(AppConstants.cropsTable, cropId);
      _crops.removeWhere((c) => c.id == cropId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
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
    }
  }

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
    DiagnosisMode diagnosisMode = DiagnosisMode.online,
    String? locationLabel,
    String? notes,
    DateTime? plantedAt,
  }) async {
    try {
      final now = DateTime.now();
      final cropId = const Uuid().v4();

      // Initial health score based on severity
      final initialScore = switch (severity) {
        Severity.severe => 25.0,
        Severity.moderate => 50.0,
        Severity.mild => 70.0,
        _ => 55.0,
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

      await _supabase.upsertCrop(_remoteMap(crop));
      await _db.upsertRow(AppConstants.cropsTable, crop.toMap());
      _crops.insert(0, crop);

      final normalizedDiseaseName = diseaseName.trim().isEmpty
          ? '${cropType.name[0].toUpperCase()}${cropType.name.substring(1)} condition'
          : diseaseName.trim();
      final diagnosis = DiagnosisModel(
        id: const Uuid().v4(),
        cropId: cropId,
        userId: userId,
        diagnosisMode: diagnosisMode,
        labelKey: labelKey.isEmpty ? null : labelKey,
        diseaseName: normalizedDiseaseName,
        confidenceScore: confidenceScore,
        severity: severity,
        resultLabel: resultLabel,
        summary: initialSummary?.trim().isEmpty == true
            ? null
            : initialSummary?.trim(),
        modelName: modelName,
        modelVersion: modelVersion,
        diagnosedAt: now,
        createdAt: now,
        updatedAt: now,
      );

      await _supabase.upsertDiagnosis(_diagnosisRemoteMap(diagnosis));
      await _db.upsertRow(AppConstants.diagnosesTable, diagnosis.toMap());

      // Create treatment
      if (treatmentSteps.isNotEmpty) {
        final treatmentId = const Uuid().v4();
        final treatment = TreatmentModel(
          id: treatmentId,
          cropId: cropId,
          diagnosisId: diagnosis.id,
          userId: userId,
          diseaseName: normalizedDiseaseName,
          treatmentTitle: 'Treatment Plan — $normalizedDiseaseName',
          treatmentSteps: treatmentSteps,
          expectedDurationDays: 14,
          status: TreatmentStatus.ongoing,
          startedAt: now,
          source: 'ai-diagnosis',
          createdAt: now,
          updatedAt: now,
        );

        await _supabase.upsertTreatment(_treatmentRemoteMap(treatment));
        await _db.upsertRow(AppConstants.treatmentsTable, treatment.toMap());

        // Create one task per treatment step
        for (var i = 0; i < treatmentSteps.length; i++) {
          final task = TreatmentTaskModel(
            id: const Uuid().v4(),
            treatmentId: treatmentId,
            cropId: cropId,
            userId: userId,
            title: treatmentSteps[i],
            dueAt: now.add(Duration(days: i)),
            status: TaskStatus.pending,
            taskOrder: i + 1,
            createdAt: now,
            updatedAt: now,
          );
          await _supabase.upsertTreatmentTask(_treatmentTaskRemoteMap(task));
          await _db.upsertRow(AppConstants.treatmentTasksTable, task.toMap());
        }
      }

      notifyListeners();
      return cropId;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Updates crop health score after a progress check-in.
  Future<void> updateCropHealthScore(
      String cropId, double score, ProgressStatus status) async {
    final idx = _crops.indexWhere((c) => c.id == cropId);
    if (idx == -1) return;
    final updated = _crops[idx].copyWith(
      latestHealthScore: score,
      latestProgressStatus: status,
      lastCheckedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await updateCrop(updated);
  }

  /// Mark a treatment task as completed both remotely (via Supabase) and
  /// in the local SQLite cache. Falls back to local-only if the remote
  /// call fails.
  ///
  /// Returns the updated task on success, or `null` on full failure.
  Future<TreatmentTaskModel?> markTaskDone(String taskId) async {
    final now = DateTime.now();
    try {
      await _supabase.markTreatmentTaskCompleted(taskId, completedAt: now);
    } catch (_) {
      // Continue with local update even if remote fails — sync_service
      // will push it later.
    }

    // Update local cache. DatabaseHelper exposes its underlying Database
    // via the `database` getter (see database_helper.dart:16).
    try {
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
      await _db.upsertRow(AppConstants.treatmentTasksTable, updated.toMap());
      await recomputeHealthScoreForCrop(updated.cropId);
      notifyListeners();
      return updated;
    } catch (_) {
      return null;
    }
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

    throw const FormatException('Unsupported file type. Choose a JSON or CSV file.');
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
