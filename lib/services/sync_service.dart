import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/app_enums.dart';
import '../core/utils/image_reference.dart';
import '../data/local/database_helper.dart';
import '../data/remote/ai_backend_service.dart';
import '../data/remote/supabase_service.dart';

/// Bidirectional sync between SQLite and Supabase.
///
/// Push  – drains the [sync_queue] table and replays mutations to Supabase.
/// Pull  – fetches remote changes newer than [lastSyncedAt] and merges them
///          into the local cache.
class SyncService {
  final SupabaseService supabaseService;
  final DatabaseHelper dbHelper;
  late final AiBackendService _aiBackend =
      AiBackendService(supabase: supabaseService);

  bool _isSyncing = false;

  SyncService({
    required this.supabaseService,
    required this.dbHelper,
  }) {
    _listenForConnectivity();
    supabaseService.authStateChanges.listen((state) {
      if (state.session != null) {
        syncAll();
      }
    });
    if (supabaseService.isSignedIn) {
      Future<void>.microtask(syncAll);
    }
  }

  // ─── Connectivity Listener ────────────────────────────────────────────────

  void _listenForConnectivity() {
    Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && supabaseService.isSignedIn) {
        syncAll();
      }
    });
  }

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Runs a full push + pull cycle.
  Future<void> syncAll() async {
    await pushPendingChanges();
    final userId = supabaseService.currentUser?.id;
    if (userId == null) return;

    await _reassessPendingPhotoCheckIns(userId);
    await pullFromRemote(userId: userId);
  }

  // ─── Push ──────────────────────────────────────────────────────────────────

  Future<void> pushPendingChanges() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final pending = await dbHelper.getPendingSyncItems();
      for (final item in pending) {
        final int itemId = item['id'] as int;
        final String table = item['table_name'] as String;
        final String op = item['operation'] as String;
        final Map<String, dynamic> payload =
            jsonDecode(item['payload'] as String) as Map<String, dynamic>;

        try {
          switch (op) {
            case 'UPSERT':
              final preparedPayload = await _preparePayloadForSync(
                table: table,
                payload: payload,
              );
              await supabaseService.upsertRecord(
                table: table,
                data: preparedPayload,
              );
              if (table == AppConstants.progressUpdatesTable) {
                await _cacheSyncedProgressImage(
                  localPayload: payload,
                  syncedPayload: preparedPayload,
                );
              }
              break;
            case 'DELETE':
              await supabaseService.deleteRecord(
                  table: table, id: payload['id'] as String);
              break;
          }
          await dbHelper.markSyncItemDone(itemId);
        } catch (e) {
          await dbHelper.incrementSyncAttempts(itemId, error: e.toString());
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _cacheSyncedProgressImage({
    required Map<String, dynamic> localPayload,
    required Map<String, dynamic> syncedPayload,
  }) async {
    final remoteImageUrl = normalizeImageReference(syncedPayload['image_url']);
    if (remoteImageUrl == null || !isRemoteImageReference(remoteImageUrl)) {
      return;
    }

    final cached = Map<String, dynamic>.from(localPayload)
      ..['image_url'] = remoteImageUrl;
    await dbHelper.upsertRow(AppConstants.progressUpdatesTable, cached);
  }

  Future<void> _reassessPendingPhotoCheckIns(String userId) async {
    final updates = await dbHelper.queryByUserId(
      AppConstants.progressUpdatesTable,
      userId,
    );
    final pending = updates.where((update) {
      final imageUrl = normalizeImageReference(update['image_url']);
      return update['progress_status'] ==
              ProgressStatus.insufficientData.value &&
          imageUrl != null;
    }).toList();

    for (final update in pending) {
      try {
        await _reassessPhotoCheckIn(update, userId);
      } catch (_) {
        // Keep the stored update pending so the next online sync can retry.
      }
    }
  }

  Future<void> _reassessPhotoCheckIn(
    Map<String, dynamic> update,
    String userId,
  ) async {
    final imageUrl = normalizeImageReference(update['image_url']);
    final cropId = update['crop_id'] as String?;
    if (imageUrl == null || cropId == null || cropId.isEmpty) {
      return;
    }

    final crop = await dbHelper.queryById(AppConstants.cropsTable, cropId);
    if (crop == null) {
      return;
    }

    final previousUpdates = await dbHelper.queryProgressUpdatesForCrop(cropId);
    final currentId = update['id'] as String?;
    final previous = previousUpdates
        .where((item) => item['id'] != currentId)
        .toList()
      ..sort((a, b) =>
          (b['update_date'] as String).compareTo(a['update_date'] as String));
    final lastUpdate = previous.isEmpty ? null : previous.first;

    final response = await _aiBackend.assessCropHealth(
      cropType: crop['crop_type'] as String? ?? 'unknown',
      diseaseName:
          (update['detected_disease_name'] as String?)?.trim().isNotEmpty ==
                  true
              ? update['detected_disease_name'] as String
              : crop['crop_name'] as String? ?? 'crop condition',
      imageDataUrl: imageUrl,
      previousImageReference: normalizeImageReference(lastUpdate?['image_url']),
      previousAssessment: lastUpdate?['note'] as String?,
      previousProgressStatus: lastUpdate?['progress_status'] as String?,
      previousUpdateDate: lastUpdate?['update_date'] as String?,
      note: update['note'] as String?,
      currentHealthScore: (crop['latest_health_score'] as num?)?.toDouble(),
    );
    if (!response.accepted) {
      return;
    }

    final now = DateTime.now().toIso8601String();
    final progressStatus = _progressStatusValue(response.progressStatus);
    final assessedUpdate = Map<String, dynamic>.from(update)
      ..['image_url'] = imageUrl
      ..['health_score'] = response.healthScore
      ..['progress_status'] = progressStatus
      ..['note'] = response.assessment.trim().isEmpty
          ? update['note']
          : response.assessment.trim()
      ..['updated_at'] = now;
    final assessedCrop = Map<String, dynamic>.from(crop)
      ..['latest_health_score'] = response.healthScore
      ..['latest_progress_status'] = progressStatus
      ..['last_checked_at'] = now
      ..['updated_at'] = now;

    await dbHelper.upsertRow(AppConstants.progressUpdatesTable, assessedUpdate);
    await dbHelper.upsertRow(AppConstants.cropsTable, assessedCrop);
    await supabaseService.upsertRecord(
      table: AppConstants.progressUpdatesTable,
      data: assessedUpdate,
    );
    await supabaseService.upsertRecord(
      table: AppConstants.cropsTable,
      data: assessedCrop,
    );
  }

  String _progressStatusValue(String value) {
    switch (value.trim().toLowerCase()) {
      case 'improving':
        return ProgressStatus.improving.value;
      case 'declining':
      case 'critical':
      case 'worsening':
        return ProgressStatus.worsening.value;
      case 'insufficient_data':
        return ProgressStatus.insufficientData.value;
      default:
        return ProgressStatus.stable.value;
    }
  }

  // ─── Pull ──────────────────────────────────────────────────────────────────

  Future<void> pullFromRemote({required String userId}) async {
    final prefs = await SharedPreferences.getInstance();
    // Pull updated profile
    final profile = await supabaseService.getProfile(userId);
    if (profile != null) {
      await dbHelper.upsertUser(profile);
    }

    final crops = await supabaseService.getCrops(userId);
    final diagnoses = await supabaseService.getDiagnoses(userId);
    final treatments = await supabaseService.getTreatments(userId);
    final tasks = await supabaseService.getTreatmentTasksByUser(userId);
    final notifications = await supabaseService.getNotifications(userId);
    final sessions = await supabaseService.getChatSessions(userId);

    final cropsToUpsert = await _newerRemoteRows(
      table: AppConstants.cropsTable,
      userId: userId,
      remoteRows: crops,
    );
    final diagnosesToUpsert = await _newerRemoteRows(
      table: AppConstants.diagnosesTable,
      userId: userId,
      remoteRows: diagnoses,
    );
    final treatmentsToUpsert = await _newerRemoteRows(
      table: AppConstants.treatmentsTable,
      userId: userId,
      remoteRows: treatments,
    );
    final tasksToUpsert = await _newerRemoteRows(
      table: AppConstants.treatmentTasksTable,
      userId: userId,
      remoteRows: tasks,
    );
    final sessionsToUpsert = await _newerRemoteRows(
      table: AppConstants.chatSessionsTable,
      userId: userId,
      remoteRows: sessions,
    );

    await dbHelper.upsertRows(AppConstants.cropsTable, cropsToUpsert);
    await dbHelper.upsertRows(
        AppConstants.diagnosesTable, _encodeNestedValues(diagnosesToUpsert));
    // Supabase returns list-type columns (e.g. treatment_steps,
    // observed_symptoms) as Dart Lists. SQLite only supports scalar types, so
    // encode any nested List/Map values to JSON strings before local upsert.
    await dbHelper.upsertRows(
        AppConstants.treatmentsTable, _encodeNestedValues(treatmentsToUpsert));
    await dbHelper.upsertRows(AppConstants.treatmentTasksTable, tasksToUpsert);
    await dbHelper.upsertRows(AppConstants.notificationsTable, notifications);
    await dbHelper.upsertRows(AppConstants.chatSessionsTable, sessionsToUpsert);

    final progressRows = <Map<String, dynamic>>[];
    for (final crop in crops) {
      final cropId = crop['id'] as String?;
      if (cropId == null || cropId.isEmpty) {
        continue;
      }
      progressRows.addAll(await supabaseService.getProgressUpdates(cropId));
    }
    final progressToUpsert = await _newerRemoteRows(
      table: AppConstants.progressUpdatesTable,
      userId: userId,
      remoteRows: progressRows,
    );
    await dbHelper.upsertRows(AppConstants.progressUpdatesTable,
        _encodeNestedValues(progressToUpsert));

    final messageRows = <Map<String, dynamic>>[];
    for (final session in sessions) {
      final sessionId = session['id'] as String?;
      if (sessionId == null || sessionId.isEmpty) {
        continue;
      }
      messageRows.addAll(await supabaseService.getChatMessages(sessionId));
    }
    final messagesToInsert = await _remoteRowsMissingLocally(
      table: AppConstants.chatMessagesTable,
      userId: userId,
      remoteRows: messageRows,
    );
    await dbHelper.upsertRows(AppConstants.chatMessagesTable, messagesToInsert);

    await prefs.setString(
      AppConstants.keyLastSyncedAt,
      DateTime.now().toIso8601String(),
    );
  }

  /// Encodes any nested [List] or [Map] values in [rows] to JSON strings so
  /// they can be stored in SQLite, which only supports scalar types.
  static List<Map<String, dynamic>> _encodeNestedValues(
      List<Map<String, dynamic>> rows) {
    return rows.map((row) {
      final prepared = Map<String, dynamic>.from(row);
      for (final key in prepared.keys.toList()) {
        final value = prepared[key];
        if (value is List || value is Map) {
          prepared[key] = jsonEncode(value);
        }
      }
      return prepared;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _newerRemoteRows({
    required String table,
    required String userId,
    required List<Map<String, dynamic>> remoteRows,
  }) async {
    final localRows = await dbHelper.queryByUserId(table, userId);
    final localUpdatedAt = <String, String>{
      for (final row in localRows)
        if ((row['id'] as String?)?.trim().isNotEmpty ?? false)
          (row['id'] as String).trim(): (row['updated_at'] as String?) ?? '',
    };
    return remoteRows.where((remoteRow) {
      final id = (remoteRow['id'] as String?)?.trim() ?? '';
      if (id.isEmpty) return true;
      final localTimestamp = localUpdatedAt[id];
      if (localTimestamp == null) return true;
      final remoteTimestamp = (remoteRow['updated_at'] as String?) ?? '';
      return remoteTimestamp.compareTo(localTimestamp) >= 0;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _remoteRowsMissingLocally({
    required String table,
    required String userId,
    required List<Map<String, dynamic>> remoteRows,
  }) async {
    final localRows = await dbHelper.queryByUserId(table, userId);
    final localIds = localRows
        .map((row) => (row['id'] as String?)?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    return remoteRows.where((row) {
      final id = (row['id'] as String?)?.trim() ?? '';
      return id.isEmpty || !localIds.contains(id);
    }).toList();
  }

  Future<Map<String, dynamic>> _preparePayloadForSync({
    required String table,
    required Map<String, dynamic> payload,
  }) async {
    final prepared = Map<String, dynamic>.from(payload);

    if (table == AppConstants.chatMessagesTable) {
      final metadata = _parseMetadata(prepared['metadata']);
      if (metadata != null) {
        await _replaceInlineImageReference(
          container: metadata,
          key: 'image_url',
          userId: prepared['user_id'] as String?,
          recordId: prepared['id'] as String?,
        );
        prepared['metadata'] = metadata;
      }
      return prepared;
    }

    if (table == AppConstants.diagnosesTable ||
        table == AppConstants.progressUpdatesTable) {
      await _replaceInlineImageReference(
        container: prepared,
        key: 'image_url',
        userId: prepared['user_id'] as String?,
        recordId: prepared['id'] as String?,
      );
      final videoUrl = normalizeImageReference(prepared['video_url']);
      if (videoUrl != null && !isRemoteImageReference(videoUrl)) {
        prepared.remove('video_url');
      }
    }

    return prepared;
  }

  Map<String, dynamic>? _parseMetadata(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }
    return null;
  }

  Future<void> _replaceInlineImageReference({
    required Map<String, dynamic> container,
    required String key,
    required String? userId,
    required String? recordId,
  }) async {
    final imageRef = normalizeImageReference(container[key]);
    final imageBytes = decodeInlineImageDataUrl(imageRef);
    if (imageBytes == null) {
      return;
    }

    if (userId == null ||
        userId.trim().isEmpty ||
        recordId == null ||
        recordId.trim().isEmpty) {
      throw StateError('Missing identifiers for queued image upload.');
    }

    final uploadedUrl = await supabaseService.uploadChatImage(
      userId: userId,
      messageId: recordId,
      bytes: imageBytes,
    );
    if (uploadedUrl == null || uploadedUrl.trim().isEmpty) {
      throw StateError('Could not upload queued image for $recordId.');
    }

    container[key] = uploadedUrl;
  }

  // ─── Queue Helpers (call before DB write when offline) ────────────────────

  Future<void> queueUpsert({
    required String tableName,
    required String recordId,
    required Map<String, dynamic> data,
  }) async {
    await dbHelper.addToSyncQueue(
      tableName: tableName,
      recordId: recordId,
      operation: 'UPSERT',
      payload: jsonEncode(data),
    );
  }

  Future<void> queueDelete({
    required String tableName,
    required String recordId,
  }) async {
    await dbHelper.addToSyncQueue(
      tableName: tableName,
      recordId: recordId,
      operation: 'DELETE',
      payload: jsonEncode({'id': recordId}),
    );
  }
}
