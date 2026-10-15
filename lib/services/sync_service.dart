import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final StreamController<void> _remoteCropChanges =
      StreamController<void>.broadcast();
  late final AiBackendService _aiBackend =
      AiBackendService(supabase: supabaseService);

  bool _isSyncing = false;
  bool _isRefreshingRemoteCrops = false;
  String? _subscribedCropUserId;
  RealtimeChannel? _cropChangesChannel;
  Future<void>? _activeSync;
  int _queueRevision = 0;
  int _completedQueueRevision = 0;

  SyncService({
    required this.supabaseService,
    required this.dbHelper,
  }) {
    _listenForConnectivity();
    supabaseService.authStateChanges.listen((state) {
      final userId = state.session?.user.id;
      if (userId == null) {
        unawaited(_removeCropChangesChannel());
      } else {
        unawaited(_subscribeToCropChanges(userId));
        unawaited(syncAll());
      }
    });
    if (supabaseService.isSignedIn) {
      final userId = supabaseService.currentUser?.id;
      if (userId != null) unawaited(_subscribeToCropChanges(userId));
      Future<void>.microtask(syncAll);
    }
  }

  Stream<void> get remoteCropChanges => _remoteCropChanges.stream;

  Future<void> _subscribeToCropChanges(String userId) async {
    if (_subscribedCropUserId == userId) return;
    await _removeCropChangesChannel();

    _subscribedCropUserId = userId;
    final channel =
        supabaseService.client.channel('crop-sync-$userId').onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: AppConstants.cropsTable,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: userId,
              ),
              callback: (_) => unawaited(_refreshAfterRemoteCropChange()),
            );
    _cropChangesChannel = channel;
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        debugPrint(
          '[SyncService] Crop realtime subscription $status: $error',
        );
      }
    });
  }

  Future<void> _removeCropChangesChannel() async {
    final channel = _cropChangesChannel;
    _cropChangesChannel = null;
    _subscribedCropUserId = null;
    if (channel != null) {
      await supabaseService.client.removeChannel(channel);
    }
  }

  Future<void> _refreshAfterRemoteCropChange() async {
    if (_isRefreshingRemoteCrops) return;
    _isRefreshingRemoteCrops = true;
    try {
      await syncAll();
      _remoteCropChanges.add(null);
    } catch (error, stackTrace) {
      debugPrint(
        '[SyncService] Could not refresh after a remote crop change: '
        '$error\n$stackTrace',
      );
    } finally {
      _isRefreshingRemoteCrops = false;
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
    final activeSync = _activeSync;
    if (activeSync != null) {
      await activeSync;
      if (_completedQueueRevision < _queueRevision) await syncAll();
      return;
    }

    final queueRevisionAtStart = _queueRevision;
    final sync = _runSyncAll();
    _activeSync = sync;
    try {
      await sync;
    } finally {
      _completedQueueRevision = queueRevisionAtStart;
      if (identical(_activeSync, sync)) _activeSync = null;
    }
    if (_queueRevision > queueRevisionAtStart) await syncAll();
  }

  Future<void> _runSyncAll() async {
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
      final pending =
          orderPendingSyncItems(await dbHelper.getPendingSyncItems());
      final failedCropIds = <String>{};
      final failedChatSessionIds = <String>{};
      final failedDiagnosisIds = <String>{};
      final syncedTreatmentIds = <String>{};
      final failedTreatmentIds = <String>{};
      for (final item in pending) {
        final int itemId = item['id'] as int;
        final String table = item['table_name'] as String;
        final String op = item['operation'] as String;
        final payloadJson = await dbHelper.getPendingSyncItemPayload(itemId);
        if (payloadJson == null) {
          debugPrint(
            '[SyncService] Pending $table record ${item['record_id']} '
            'has no queue payload; leaving it queued.',
          );
          continue;
        }
        final Map<String, dynamic> payload =
            jsonDecode(payloadJson) as Map<String, dynamic>;

        final cropId = payload['crop_id'] as String?;
        final diagnosisId = payload['diagnosis_id'] as String?;
        final chatSessionId = payload['chat_session_id'] as String?;
        final treatmentId = payload['treatment_id'] as String?;
        final sessionId = payload['session_id'] as String?;
        final blockedByFailedParent =
            (table == AppConstants.chatSessionsTable &&
                    cropId != null &&
                    failedCropIds.contains(cropId)) ||
                (table == AppConstants.diagnosesTable &&
                    ((cropId != null && failedCropIds.contains(cropId)) ||
                        (chatSessionId != null &&
                            failedChatSessionIds.contains(chatSessionId)))) ||
                (table == AppConstants.treatmentsTable &&
                    ((cropId != null && failedCropIds.contains(cropId)) ||
                        (diagnosisId != null &&
                            failedDiagnosisIds.contains(diagnosisId)))) ||
                (table == AppConstants.notificationsTable &&
                    ((cropId != null && failedCropIds.contains(cropId)) ||
                        (treatmentId != null &&
                            failedTreatmentIds.contains(treatmentId)))) ||
                (table == AppConstants.treatmentTasksTable &&
                    ((cropId != null && failedCropIds.contains(cropId)) ||
                        (treatmentId != null &&
                            failedTreatmentIds.contains(treatmentId)))) ||
                (table == AppConstants.progressUpdatesTable &&
                    ((cropId != null && failedCropIds.contains(cropId)) ||
                        (treatmentId != null &&
                            failedTreatmentIds.contains(treatmentId)) ||
                        (diagnosisId != null &&
                            failedDiagnosisIds.contains(diagnosisId)))) ||
                (table == AppConstants.chatMessagesTable &&
                    sessionId != null &&
                    failedChatSessionIds.contains(sessionId));
        if (blockedByFailedParent) {
          debugPrint(
            '[SyncService] Deferred $table record ${payload['id'] ?? item['record_id']} '
            'because a queued parent failed to sync.',
          );
          final recordId =
              payload['id'] as String? ?? item['record_id'] as String?;
          if (recordId != null) {
            if (table == AppConstants.chatSessionsTable) {
              failedChatSessionIds.add(recordId);
            } else if (table == AppConstants.diagnosesTable) {
              failedDiagnosisIds.add(recordId);
            } else if (table == AppConstants.treatmentsTable) {
              failedTreatmentIds.add(recordId);
            }
          }
          continue;
        }

        if (table == AppConstants.treatmentTasksTable && op == 'UPSERT') {
          if (treatmentId == null || treatmentId.trim().isEmpty) {
            debugPrint(
              '[SyncService] Deferred task ${payload['id']} because it has '
              'no treatment_id.',
            );
            continue;
          }
          if (!syncedTreatmentIds.contains(treatmentId)) {
            if (failedTreatmentIds.contains(treatmentId)) continue;

            final localTreatment = await dbHelper.queryById(
              AppConstants.treatmentsTable,
              treatmentId,
            );
            if (localTreatment == null) {
              failedTreatmentIds.add(treatmentId);
              debugPrint(
                '[SyncService] Deferred task ${payload['id']} because its '
                'treatment $treatmentId is missing locally.',
              );
              continue;
            }

            try {
              await supabaseService.upsertRecord(
                table: AppConstants.treatmentsTable,
                data: _prepareLocalTreatmentForSync(localTreatment),
              );
              syncedTreatmentIds.add(treatmentId);
            } catch (error) {
              failedTreatmentIds.add(treatmentId);
              debugPrint(
                '[SyncService] Deferred tasks for treatment $treatmentId '
                'because the treatment could not be synced: $error',
              );
              continue;
            }
          }
        }

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
            case 'SOFT_DELETE':
              await supabaseService.softDeleteRecord(
                table: table,
                id: payload['id'] as String,
              );
              break;
          }
          if (table == AppConstants.treatmentsTable && op == 'UPSERT') {
            final treatmentId =
                payload['id'] as String? ?? item['record_id'] as String?;
            if (treatmentId != null) syncedTreatmentIds.add(treatmentId);
          }
          await dbHelper.markSyncItemDone(itemId);
        } catch (e, stackTrace) {
          if (table == AppConstants.treatmentsTable && op == 'UPSERT') {
            final treatmentId =
                payload['id'] as String? ?? item['record_id'] as String?;
            if (treatmentId != null) failedTreatmentIds.add(treatmentId);
          }
          if (op == 'UPSERT') {
            final recordId =
                payload['id'] as String? ?? item['record_id'] as String?;
            if (recordId != null) {
              if (table == AppConstants.cropsTable) {
                failedCropIds.add(recordId);
              } else if (table == AppConstants.chatSessionsTable) {
                failedChatSessionIds.add(recordId);
              } else if (table == AppConstants.diagnosesTable) {
                failedDiagnosisIds.add(recordId);
              }
            }
          }
          debugPrint(
            '[SyncService] Failed to sync $op $table record '
            '${payload['id'] ?? item['record_id']}: $e\n$stackTrace',
          );
          await dbHelper.incrementSyncAttempts(itemId, error: e.toString());
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  @visibleForTesting
  static List<Map<String, dynamic>> orderPendingSyncItems(
    Iterable<Map<String, dynamic>> items,
  ) {
    final pending = items.toList(growable: false);
    final indices = List<int>.generate(pending.length, (index) => index);
    indices.sort((leftIndex, rightIndex) {
      final leftTable = pending[leftIndex]['table_name'] as String? ?? '';
      final rightTable = pending[rightIndex]['table_name'] as String? ?? '';
      final priorityDifference =
          _syncPriority(leftTable) - _syncPriority(rightTable);
      return priorityDifference != 0
          ? priorityDifference
          : leftIndex.compareTo(rightIndex);
    });
    return [for (final index in indices) pending[index]];
  }

  static int _syncPriority(String table) {
    if (table == AppConstants.cropsTable) return 0;
    if (table == AppConstants.chatSessionsTable) return 1;
    if (table == AppConstants.diagnosesTable) return 2;
    if (table == AppConstants.treatmentsTable) return 3;
    if (table == AppConstants.treatmentTasksTable) return 4;
    return 5;
  }

  Map<String, dynamic> _prepareLocalTreatmentForSync(
    Map<String, dynamic> treatment,
  ) {
    final prepared = Map<String, dynamic>.from(treatment);
    final rawSteps = prepared['treatment_steps'];
    if (rawSteps is String && rawSteps.isNotEmpty) {
      final decoded = jsonDecode(rawSteps);
      if (decoded is! List) {
        throw const FormatException('Treatment steps must be a JSON list.');
      }
      prepared['treatment_steps'] =
          decoded.map((step) => step.toString()).toList();
    } else if (rawSteps == null) {
      prepared['treatment_steps'] = <String>[];
    }
    prepared['reassessment_required'] =
        prepared['reassessment_required'] == true ||
            prepared['reassessment_required'] == 1;
    prepared['is_deleted'] =
        prepared['is_deleted'] == true || prepared['is_deleted'] == 1;
    return prepared;
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

    // Include tombstones so changes made from the admin console propagate to
    // devices instead of leaving deleted rows active in the local cache.
    final crops = await supabaseService.getCropsIncludingDeleted(userId);
    final diagnoses =
        await supabaseService.getDiagnosesIncludingDeleted(userId);
    final treatments =
        await supabaseService.getTreatmentsIncludingDeleted(userId);
    final tasks = await supabaseService.getAllTreatmentTasksByUser(userId);
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
        if (value is bool) {
          prepared[key] = value ? 1 : 0;
        } else if (value is DateTime) {
          prepared[key] = value.toIso8601String();
        } else if (value is List || value is Map) {
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
    final localRows = await dbHelper.queryByUserId(
      table,
      userId,
      includeDeleted: true,
    );
    final queuedRows = (await dbHelper.getPendingSyncItems()).where((item) =>
        item['table_name'] == table &&
        (item['operation'] == 'UPSERT' || item['operation'] == 'SOFT_DELETE'));
    final pendingIds = queuedRows
        .map((item) => item['record_id'] as String?)
        .whereType<String>()
        .toSet();
    final localUpdatedAt = <String, String>{
      for (final row in localRows)
        if ((row['id'] as String?)?.trim().isNotEmpty ?? false)
          (row['id'] as String).trim(): (row['updated_at'] as String?) ?? '',
    };
    return remoteRows.where((remoteRow) {
      final id = (remoteRow['id'] as String?)?.trim() ?? '';
      if (id.isEmpty) return true;
      if (pendingIds.contains(id)) return false;
      final localTimestamp = localUpdatedAt[id];
      if (localTimestamp == null) return true;
      final remoteTimestamp = (remoteRow['updated_at'] as String?) ?? '';
      return remoteTimestampIsAtLeastAsNew(
        remoteTimestamp: remoteTimestamp,
        localTimestamp: localTimestamp,
      );
    }).toList();
  }

  static bool remoteTimestampIsAtLeastAsNew({
    required String remoteTimestamp,
    required String localTimestamp,
  }) {
    final remoteDate = DateTime.tryParse(remoteTimestamp);
    final localDate = DateTime.tryParse(localTimestamp);
    if (remoteDate != null && localDate != null) {
      return !remoteDate.isBefore(localDate);
    }
    return remoteTimestamp.compareTo(localTimestamp) >= 0;
  }

  static List<Map<String, dynamic>> mergeLocalAndRemoteRows({
    required Iterable<Map<String, dynamic>> localRows,
    required Iterable<Map<String, dynamic>> remoteRows,
    Set<String> pendingLocalIds = const {},
  }) {
    final merged = <String, Map<String, dynamic>>{};
    for (final row in localRows) {
      final id = (row['id'] as String?)?.trim();
      if (id != null && id.isNotEmpty) {
        merged[id] = Map<String, dynamic>.from(row);
      }
    }
    for (final row in remoteRows) {
      final id = (row['id'] as String?)?.trim();
      if (id == null || id.isEmpty) continue;
      final local = merged[id];
      if (pendingLocalIds.contains(id)) {
        continue;
      }
      if (local == null) {
        merged[id] = Map<String, dynamic>.from(row);
        continue;
      }

      final localTimestamp = local['updated_at'] as String? ?? '';
      final remoteTimestamp = row['updated_at'] as String? ?? '';
      if (remoteTimestampIsAtLeastAsNew(
        remoteTimestamp: remoteTimestamp,
        localTimestamp: localTimestamp,
      )) {
        merged[id] = Map<String, dynamic>.from(row);
      }
    }
    return merged.values.toList(growable: false);
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
    _queueRevision++;
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
    _queueRevision++;
  }

  Future<void> queueSoftDelete({
    required String tableName,
    required String recordId,
  }) async {
    await dbHelper.addToSyncQueue(
      tableName: tableName,
      recordId: recordId,
      operation: 'SOFT_DELETE',
      payload: jsonEncode({'id': recordId}),
    );
    _queueRevision++;
  }
}
