import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/image_reference.dart';
import '../data/local/database_helper.dart';
import '../data/remote/supabase_service.dart';

/// Bidirectional sync between SQLite and Supabase.
///
/// Push  – drains the [sync_queue] table and replays mutations to Supabase.
/// Pull  – fetches remote changes newer than [lastSyncedAt] and merges them
///          into the local cache.
class SyncService {
  final SupabaseService supabaseService;
  final DatabaseHelper dbHelper;

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
    if (userId != null) await pullFromRemote(userId: userId);
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

    await dbHelper.upsertRows(AppConstants.cropsTable, crops);
    await dbHelper.upsertRows(AppConstants.diagnosesTable, diagnoses);
    await dbHelper.upsertRows(AppConstants.treatmentsTable, treatments);
    await dbHelper.upsertRows(AppConstants.treatmentTasksTable, tasks);
    await dbHelper.upsertRows(AppConstants.notificationsTable, notifications);
    await dbHelper.upsertRows(AppConstants.chatSessionsTable, sessions);

    final progressRows = <Map<String, dynamic>>[];
    for (final crop in crops) {
      final cropId = crop['id'] as String?;
      if (cropId == null || cropId.isEmpty) {
        continue;
      }
      progressRows.addAll(await supabaseService.getProgressUpdates(cropId));
    }
    await dbHelper.upsertRows(AppConstants.progressUpdatesTable, progressRows);

    final messageRows = <Map<String, dynamic>>[];
    for (final session in sessions) {
      final sessionId = session['id'] as String?;
      if (sessionId == null || sessionId.isEmpty) {
        continue;
      }
      messageRows.addAll(await supabaseService.getChatMessages(sessionId));
    }
    await dbHelper.upsertRows(AppConstants.chatMessagesTable, messageRows);

    await prefs.setString(
      AppConstants.keyLastSyncedAt,
      DateTime.now().toIso8601String(),
    );
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
