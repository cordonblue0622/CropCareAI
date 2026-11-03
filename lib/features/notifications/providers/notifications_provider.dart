import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_enums.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/models/treatment_task_model.dart';
import '../../../data/remote/supabase_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/sync_service.dart';

class NotificationsProvider extends ChangeNotifier {
  final SupabaseService _supabase;
  final DatabaseHelper _db;
  final SyncService _sync;

  List<NotificationModel> _notifications = [];
  final Set<String> _locallyDeletedNotificationIds = <String>{};
  List<TreatmentTaskModel> _todayTasks = [];
  List<TreatmentTaskModel> _missedTasks = [];
  List<TreatmentTaskModel> _tomorrowTasks = [];
  List<TreatmentTaskModel> _upcomingTasks = [];
  List<TreatmentTaskModel> _pendingTasks = [];
  bool _isLoading = false;
  bool _hasLoadedCache = false;
  String? _loadedUserId;
  Timer? _overdueRefreshTimer;

  NotificationsProvider({
    required SupabaseService supabase,
    required DatabaseHelper db,
    required SyncService sync,
  })  : _supabase = supabase,
        _db = db,
        _sync = sync;

  @override
  void dispose() {
    _overdueRefreshTimer?.cancel();
    super.dispose();
  }

  List<NotificationModel> get notifications => _notifications;
  List<NotificationModel> get unread =>
      _notifications.where((n) => !n.isRead).toList();
  List<TreatmentTaskModel> get todayTasks => _todayTasks;
  List<TreatmentTaskModel> get missedTasks => _missedTasks;
  List<TreatmentTaskModel> get tomorrowTasks => _tomorrowTasks;
  List<TreatmentTaskModel> get upcomingTasks => _upcomingTasks;
  List<TreatmentTaskModel> get pendingTasks => _pendingTasks;
  bool get isLoading => _isLoading;
  int get unreadCount => unread.length;
  int get alertCount {
    final alerts = _notifications.where((notification) =>
        !notification.isRead &&
        (notification.type == NotificationType.general ||
            notification.type == NotificationType.progressAlert ||
            notification.type == NotificationType.treatmentReminder));
    return alerts
        .map((notification) => notification.cropId ?? notification.id)
        .toSet()
        .length;
  }

  // ─── Fetch ────────────────────────────────────────────────────────────────

  Future<void> fetchAll(String userId) async {
    if (_loadedUserId != userId) {
      _notifications = [];
      _locallyDeletedNotificationIds.clear();
      _todayTasks = [];
      _missedTasks = [];
      _tomorrowTasks = [];
      _upcomingTasks = [];
      _pendingTasks = [];
      _loadedUserId = userId;
      _hasLoadedCache = false;
    }
    _isLoading = !_hasLoadedCache;
    notifyListeners();

    await _loadLocalCache(userId);
    _hasLoadedCache = true;
    _isLoading = false;
    notifyListeners();

    // Push queued offline edits before reading the cloud snapshot.
    try {
      await _sync.syncAll().timeout(const Duration(seconds: 12));
    } catch (_) {
      // Keep showing the cache; failed queue items remain available for retry.
    }

    try {
      await Future.wait([
        _fetchNotifications(userId).timeout(const Duration(seconds: 10)),
        _fetchTasks(userId).timeout(const Duration(seconds: 10)),
      ]);
    } catch (_) {
      // The individual fetchers retain the cached values on network failure.
    }

    try {
      final cropTypes = await _cropTypesById(userId);
      await _syncDailyCropAlerts(userId, cropTypes);
      await _syncCropAttentionAlerts(userId, cropTypes);
      await _sync.syncAll().timeout(const Duration(seconds: 12));
    } catch (error, stackTrace) {
      debugPrint('Could not sync generated crop alerts: $error');
      debugPrintStack(stackTrace: stackTrace);
      // Alert generation retries on the next refresh.
    }

    notifyListeners();

    final notificationsAllowed =
        await NotificationService.instance.requestPermission();
    if (notificationsAllowed) {
      await NotificationService.instance.scheduleForTasks(
        _pendingTasks,
        cropNames: await _cropTypesById(userId),
      );
    }
  }

  Future<void> _loadLocalCache(String userId) async {
    try {
      final deletedCropIds = await _deletedCropIds(userId);
      final pendingDeleteIds = await _pendingNotificationDeleteIds();
      final notificationRows =
          await _db.queryByUserId(AppConstants.notificationsTable, userId);
      _notifications = notificationRows
          .map(NotificationModel.fromMap)
          .where((notification) =>
              (notification.cropId == null ||
                  !deletedCropIds.contains(notification.cropId)) &&
              !pendingDeleteIds.contains(notification.id))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final taskRows = await _db.queryByUserId(
        AppConstants.treatmentTasksTable,
        userId,
        includeDeleted: true,
      );
      final tasks = taskRows
          .map(TreatmentTaskModel.fromMap)
          .where((task) => !deletedCropIds.contains(task.cropId))
          .toList();
      _pendingTasks = tasks
          .where((task) => !task.isDeleted && task.status == TaskStatus.pending)
          .toList(growable: false);
      _bucketTasks(_pendingTasks);
    } catch (_) {
      // The local database can be unavailable on web or before initialization.
    }
  }

  Future<void> _fetchNotifications(String userId) async {
    try {
      final rows = await _supabase.getNotifications(userId);
      final localRows =
          await _db.queryByUserId(AppConstants.notificationsTable, userId);
      final deletedCropIds = await _deletedCropIds(userId);
      final pendingDeleteIds = await _pendingNotificationDeleteIds();
      final pendingUpserts = (await _db.getPendingSyncItems())
          .where((item) =>
              item['table_name'] == AppConstants.notificationsTable &&
              item['operation'] == 'UPSERT')
          .map((item) => item['record_id'] as String?)
          .whereType<String>()
          .toSet();
      final merged = <String, NotificationModel>{};
      for (final row in rows) {
        final notification = NotificationModel.fromMap(row);
        merged[notification.id] = notification;
      }
      for (final row in localRows) {
        final notification = NotificationModel.fromMap(row);
        if (pendingUpserts.contains(notification.id)) {
          merged[notification.id] = notification;
        }
      }

      _notifications = merged.values
          .where((notification) =>
              (notification.cropId == null ||
                  !deletedCropIds.contains(notification.cropId)) &&
              !pendingDeleteIds.contains(notification.id))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _db.upsertRows(
        AppConstants.notificationsTable,
        _notifications.map((notification) => notification.toMap()),
      );
    } catch (_) {
      final rows =
          await _db.queryByUserId(AppConstants.notificationsTable, userId);
      final deletedCropIds = await _deletedCropIds(userId);
      final pendingDeleteIds = await _pendingNotificationDeleteIds();
      _notifications = rows
          .map(NotificationModel.fromMap)
          .where((notification) =>
              (notification.cropId == null ||
                  !deletedCropIds.contains(notification.cropId)) &&
              !pendingDeleteIds.contains(notification.id))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
  }

  Future<Set<String>> _pendingNotificationDeleteIds() async {
    try {
      final pending = await _db.getPendingSyncItems();
      final queuedDeletes = pending
          .where((item) =>
              item['table_name'] == AppConstants.notificationsTable &&
              item['operation'] == 'DELETE')
          .map((item) => item['record_id'] as String?)
          .whereType<String>();
      return {..._locallyDeletedNotificationIds, ...queuedDeletes};
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _fetchTasks(String userId) async {
    try {
      final remoteRows = await _supabase.getAllTreatmentTasksByUser(userId);
      final localRows = await _db.queryByUserId(
        AppConstants.treatmentTasksTable,
        userId,
        includeDeleted: true,
      );
      final pendingTaskIds = (await _db.getPendingSyncItems())
          .where((item) =>
              item['table_name'] == AppConstants.treatmentTasksTable &&
              (item['operation'] == 'UPSERT' ||
                  item['operation'] == 'SOFT_DELETE'))
          .map((item) => item['record_id'] as String?)
          .whereType<String>()
          .toSet();
      final localById = <String, Map<String, dynamic>>{
        for (final row in localRows)
          if (row['id'] is String) row['id'] as String: row,
      };
      final remoteIds = <String>{};
      final merged = <String, Map<String, dynamic>>{};
      for (final remote in remoteRows) {
        final id = remote['id'] as String?;
        if (id == null || id.isEmpty) continue;
        remoteIds.add(id);
        final local = localById[id];
        if (local != null &&
            (pendingTaskIds.contains(id) || !_isAtLeastAsNew(remote, local))) {
          merged[id] = local;
        } else {
          merged[id] = remote;
        }
      }

      // Local-only tasks remain visible while their previous cloud write is
      // retried. ID keyed merging prevents duplicate counts once synced.
      var queuedLocalTasks = false;
      for (final local in localRows) {
        final id = local['id'] as String?;
        if (id != null && id.isNotEmpty && !remoteIds.contains(id)) {
          merged[id] = local;
          final task = TreatmentTaskModel.fromMap(local);
          if (!task.isDeleted && !pendingTaskIds.contains(id)) {
            final remote = task.toMap()..['is_deleted'] = task.isDeleted;
            await _sync.queueUpsert(
              tableName: AppConstants.treatmentTasksTable,
              recordId: id,
              data: remote,
            );
            queuedLocalTasks = true;
          }
        }
      }

      final mergedRows = merged.values.toList(growable: false);
      await _db.upsertRows(AppConstants.treatmentTasksTable, mergedRows);
      final deletedCropIds = await _deletedCropIds(userId);
      final allTasks = mergedRows
          .map(TreatmentTaskModel.fromMap)
          .where((task) => !deletedCropIds.contains(task.cropId))
          .toList();
      _pendingTasks = allTasks
          .where((task) => !task.isDeleted && task.status == TaskStatus.pending)
          .toList(growable: false);
      _bucketTasks(_pendingTasks);
      if (queuedLocalTasks) {
        await _sync.syncAll().timeout(const Duration(seconds: 12));
      }
    } catch (_) {
      final rows = await _db.queryByUserId(
        AppConstants.treatmentTasksTable,
        userId,
        includeDeleted: true,
      );
      final deletedCropIds = await _deletedCropIds(userId);
      final allTasks = rows
          .map(TreatmentTaskModel.fromMap)
          .where((task) => !deletedCropIds.contains(task.cropId))
          .toList();
      _pendingTasks = allTasks
          .where((task) => !task.isDeleted && task.status == TaskStatus.pending)
          .toList(growable: false);
      _bucketTasks(_pendingTasks);
    }
  }

  bool _isAtLeastAsNew(
    Map<String, dynamic> candidate,
    Map<String, dynamic> current,
  ) {
    final candidateDate = DateTime.tryParse(
      candidate['updated_at'] as String? ?? '',
    );
    final currentDate = DateTime.tryParse(
      current['updated_at'] as String? ?? '',
    );
    if (candidateDate != null && currentDate != null) {
      return !candidateDate.isBefore(currentDate);
    }
    return (candidate['updated_at'] as String? ?? '')
            .compareTo(current['updated_at'] as String? ?? '') >=
        0;
  }

  Future<Set<String>> _deletedCropIds(String userId) async {
    try {
      final rows = await _db.queryByUserId(
        AppConstants.cropsTable,
        userId,
        includeDeleted: true,
      );
      return rows
          .where((row) => row['is_deleted'] == true || row['is_deleted'] == 1)
          .map((row) => row['id'] as String?)
          .whereType<String>()
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<Map<String, String>> _cropTypesById(String userId) async {
    try {
      final rows = await _db.queryByUserId(
        AppConstants.cropsTable,
        userId,
        includeDeleted: true,
      );
      return {
        for (final row in rows)
          if (row['id'] is String &&
              row['crop_type'] is String &&
              row['is_deleted'] != true &&
              row['is_deleted'] != 1)
            row['id'] as String: row['crop_type'] as String,
      };
    } catch (_) {
      return <String, String>{};
    }
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _dailyAlertDismissalKey(String userId) =>
      'dismissed_daily_crop_task_alerts_$userId';

  bool _isDailyTaskAlert(NotificationModel notification) {
    final title = notification.title;
    return notification.type == NotificationType.treatmentReminder &&
        (title.startsWith('A new task awaits for your ') ||
            title.startsWith('New tasks await for your '));
  }

  Future<void> _rememberDismissedDailyAlert(
    NotificationModel notification,
  ) async {
    final cropId = notification.cropId;
    if (cropId == null) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      final key = _dailyAlertDismissalKey(notification.userId);
      final dismissed = preferences.getStringList(key) ?? <String>[];
      final date = notification.scheduledFor ?? notification.createdAt;
      final dismissal = '${_dateKey(date)}|$cropId';
      if (!dismissed.contains(dismissal)) dismissed.add(dismissal);
      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      dismissed.removeWhere((value) {
        final separator = value.indexOf('|');
        final dateKey = separator < 0 ? null : value.substring(0, separator);
        final date = dateKey == null ? null : DateTime.tryParse(dateKey);
        return date == null || date.isBefore(cutoff);
      });
      await preferences.setStringList(key, dismissed);
    } catch (_) {
      // The notification remains dismissible for the current session.
    }
  }

  Future<void> _syncDailyCropAlerts(
    String userId,
    Map<String, String> cropTypes,
  ) async {
    final now = DateTime.now();
    final morning = DateTime(now.year, now.month, now.day, 4);
    if (now.isBefore(morning)) return;

    final tasksByCrop = <String, List<TreatmentTaskModel>>{};
    for (final task in _todayTasks) {
      tasksByCrop
          .putIfAbsent(task.cropId, () => <TreatmentTaskModel>[])
          .add(task);
    }
    if (tasksByCrop.isEmpty) return;

    final preferences = await SharedPreferences.getInstance();
    final dismissalKey = _dailyAlertDismissalKey(userId);
    final dismissed =
        (preferences.getStringList(dismissalKey) ?? <String>[]).toSet();
    final currentDate = _dateKey(now);
    final pendingDeleteIds = await _pendingNotificationDeleteIds();

    for (final entry in tasksByCrop.entries) {
      if (dismissed.contains('$currentDate|${entry.key}')) continue;
      final id = const Uuid().v5(
        Namespace.url.value,
        'cropcareai:daily-task-alert:$userId:${entry.key}:$currentDate',
      );
      if (pendingDeleteIds.contains(id) ||
          _notifications.any((notification) => notification.id == id)) {
        continue;
      }

      final rawCropType = cropTypes[entry.key] ?? 'crop';
      final cropType = rawCropType.isEmpty
          ? 'crop'
          : rawCropType[0].toLowerCase() + rawCropType.substring(1);
      final taskCount = entry.value.length;
      final notification = NotificationModel(
        id: id,
        userId: userId,
        cropId: entry.key,
        treatmentId: entry.value.first.treatmentId,
        type: NotificationType.treatmentReminder,
        title: taskCount == 1
            ? 'A new task awaits for your $cropType crop'
            : 'New tasks await for your $cropType crop',
        body:
            'Visit your crop now to see ${taskCount == 1 ? "today's task" : "today's tasks"}.',
        scheduledFor: morning,
        createdAt: now,
      );
      _notifications.insert(0, notification);
      await _db.upsertRow(
        AppConstants.notificationsTable,
        notification.toMap(),
      );
      await _sync.queueUpsert(
        tableName: AppConstants.notificationsTable,
        recordId: notification.id,
        data: _remoteNotificationMap(notification),
      );
    }
  }

  String _dismissedCropAlertsKey(String userId) =>
      'dismissed_crop_attention_alerts_$userId';

  Future<void> _rememberDismissedCropAlert(String userId, String cropId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final key = _dismissedCropAlertsKey(userId);
      final dismissed = preferences.getStringList(key) ?? <String>[];
      if (!dismissed.contains(cropId)) {
        dismissed.add(cropId);
        await preferences.setStringList(key, dismissed);
      }
    } catch (_) {
      // The notification can still be dismissed when preferences are unavailable.
    }
  }

  Future<void> _syncCropAttentionAlerts(
    String userId,
    Map<String, String> cropTypes,
  ) async {
    final overdueByCrop = <String, TreatmentTaskModel>{};
    for (final task in _missedTasks) {
      overdueByCrop.putIfAbsent(task.cropId, () => task);
    }

    Set<String> dismissedCropIds = <String>{};
    try {
      final preferences = await SharedPreferences.getInstance();
      final key = _dismissedCropAlertsKey(userId);
      final storedDismissals =
          (preferences.getStringList(key) ?? <String>[]).toSet();
      dismissedCropIds =
          storedDismissals.intersection(overdueByCrop.keys.toSet());
      if (dismissedCropIds.length != storedDismissals.length) {
        await preferences.setStringList(key, dismissedCropIds.toList());
      }
    } catch (_) {
      // Alert generation continues if local dismissal storage is unavailable.
    }

    for (final entry in overdueByCrop.entries) {
      if (dismissedCropIds.contains(entry.key)) continue;
      final existing = _notifications.any((notification) =>
          notification.cropId == entry.key &&
          notification.type == NotificationType.progressAlert);
      if (existing) continue;

      final now = DateTime.now();
      final rawCropType = cropTypes[entry.key] ?? 'crop';
      final cropType = rawCropType.isEmpty
          ? 'crop'
          : rawCropType[0].toLowerCase() + rawCropType.substring(1);
      final notification = NotificationModel(
        id: const Uuid().v4(),
        userId: userId,
        cropId: entry.key,
        treatmentId: entry.value.treatmentId,
        type: NotificationType.progressAlert,
        title: 'Your $cropType crop needs attention',
        body: 'Visit your crop now to review its overdue care plan.',
        scheduledFor: now,
        createdAt: now,
      );
      _notifications.insert(0, notification);
      await _db.upsertRow(
        AppConstants.notificationsTable,
        notification.toMap(),
      );
      await _sync.queueUpsert(
        tableName: AppConstants.notificationsTable,
        recordId: notification.id,
        data: _remoteNotificationMap(notification),
      );
    }
  }

  void _bucketTasks(List<TreatmentTaskModel> allTasks) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final tomorrowEnd = todayEnd.add(const Duration(days: 1));
    final sevenDaysOut = todayStart.add(const Duration(days: 7));
    final overdueCutoffReached =
        !now.isBefore(DateTime(now.year, now.month, now.day, 19));

    _todayTasks = allTasks
        .where((task) =>
            !task.dueAt.toLocal().isBefore(todayStart) &&
            task.dueAt.toLocal().isBefore(todayEnd) &&
            !overdueCutoffReached &&
            task.status == TaskStatus.pending)
        .toList();

    _missedTasks = allTasks
        .where((task) =>
            (task.dueAt.toLocal().isBefore(todayStart) ||
                (overdueCutoffReached &&
                    !task.dueAt.toLocal().isBefore(todayStart) &&
                    task.dueAt.toLocal().isBefore(todayEnd))) &&
            task.status == TaskStatus.pending)
        .toList();

    _tomorrowTasks = allTasks
        .where((task) =>
            !task.dueAt.toLocal().isBefore(todayEnd) &&
            task.dueAt.toLocal().isBefore(tomorrowEnd) &&
            task.status == TaskStatus.pending)
        .toList();

    _upcomingTasks = allTasks
        .where((task) =>
            !task.dueAt.toLocal().isBefore(todayStart) &&
            task.dueAt.toLocal().isBefore(sevenDaysOut) &&
            task.status == TaskStatus.pending)
        .toList();

    _todayTasks.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    _missedTasks.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    _tomorrowTasks.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    _upcomingTasks.sort((a, b) => a.dueAt.compareTo(b.dueAt));

    _overdueRefreshTimer?.cancel();
    if (allTasks
        .any((task) => !task.isDeleted && task.status == TaskStatus.pending)) {
      final nextCutoff = DateTime(now.year, now.month, now.day, 19);
      final nextCheck = nextCutoff.isAfter(now)
          ? nextCutoff
          : nextCutoff.add(const Duration(days: 1));
      _overdueRefreshTimer = Timer(nextCheck.difference(now), () {
        _bucketTasks(_pendingTasks);
        notifyListeners();
      });
    }
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> markRead(String notificationId) async {
    final idx = _notifications.indexWhere((n) => n.id == notificationId);
    if (idx == -1) return;
    final updated = _notifications[idx].copyWith(isRead: true);
    _notifications[idx] = updated;
    notifyListeners();
    await _db.upsertRow(AppConstants.notificationsTable, updated.toMap());
    await _sync.queueUpsert(
      tableName: AppConstants.notificationsTable,
      recordId: notificationId,
      data: _remoteNotificationMap(updated),
    );
    try {
      await _supabase.markNotificationRead(notificationId);
      await _clearQueuedOperation(notificationId, 'UPSERT');
    } catch (_) {}
  }

  Future<void> deleteNotification(String notificationId) async {
    final index = _notifications.indexWhere(
      (notification) => notification.id == notificationId,
    );
    if (index == -1) return;

    final notification = _notifications[index];
    _locallyDeletedNotificationIds.add(notificationId);
    _notifications.removeAt(index);
    notifyListeners();

    if (notification.type == NotificationType.progressAlert &&
        notification.cropId != null) {
      await _rememberDismissedCropAlert(
        notification.userId,
        notification.cropId!,
      );
    }
    if (_isDailyTaskAlert(notification)) {
      await _rememberDismissedDailyAlert(notification);
    }

    // A notification created or edited while offline can still have an older
    // UPSERT queued. Remove those writes so they cannot recreate a dismissed
    // notification after the DELETE is processed.
    await _clearQueuedOperation(notificationId, 'UPSERT');
    await _queueDelete(notificationId, notification.userId);
    await _db.hardDelete(AppConstants.notificationsTable, notificationId);
    try {
      await _supabase.deleteNotification(notificationId);
      await _sync.syncAll().timeout(const Duration(seconds: 12));
      await _clearQueuedDelete(notificationId);
      _locallyDeletedNotificationIds.remove(notificationId);
    } catch (_) {}
  }

  Future<void> removeCropData(String cropId) async {
    _notifications.removeWhere((notification) => notification.cropId == cropId);
    _todayTasks.removeWhere((task) => task.cropId == cropId);
    _missedTasks.removeWhere((task) => task.cropId == cropId);
    _tomorrowTasks.removeWhere((task) => task.cropId == cropId);
    _upcomingTasks.removeWhere((task) => task.cropId == cropId);
    _pendingTasks.removeWhere((task) => task.cropId == cropId);
    _bucketTasks(_pendingTasks);

    // Publish the pruned counts before awaiting OS reminder rescheduling.
    notifyListeners();
    await NotificationService.instance.scheduleForTasks(
      _pendingTasks,
      cropNames: _loadedUserId == null
          ? const <String, String>{}
          : await _cropTypesById(_loadedUserId!),
    );
  }

  Future<void> _queueDelete(String notificationId, String userId) async {
    await _sync.queueDelete(
      tableName: AppConstants.notificationsTable,
      recordId: notificationId,
      userId: userId,
    );
  }

  Future<void> _clearQueuedDelete(String notificationId) async {
    final pending = await _db.getPendingSyncItems();
    for (final item in pending) {
      if (item['table_name'] == AppConstants.notificationsTable &&
          item['record_id'] == notificationId &&
          item['operation'] == 'DELETE') {
        await _db.markSyncItemDone(item['id'] as int);
      }
    }
  }

  Future<void> _clearQueuedOperation(
      String notificationId, String operation) async {
    final pending = await _db.getPendingSyncItems();
    for (final item in pending) {
      if (item['table_name'] == AppConstants.notificationsTable &&
          item['record_id'] == notificationId &&
          item['operation'] == operation) {
        await _db.markSyncItemDone(item['id'] as int);
      }
    }
  }

  Map<String, dynamic> _remoteNotificationMap(NotificationModel notification) {
    return {
      'id': notification.id,
      'user_id': notification.userId,
      'crop_id': notification.cropId,
      'treatment_id': notification.treatmentId,
      'type': notification.type.value,
      'title': notification.title,
      'body': notification.body,
      'scheduled_for': notification.scheduledFor?.toIso8601String(),
      'is_read': notification.isRead,
      'is_sent': notification.isSent,
      'created_at': notification.createdAt.toIso8601String(),
    };
  }

  /// Marks the task complete in remote + local stores. Returns the affected
  /// crop's id so callers can refresh derived state (e.g. Farm Vitality).
  /// Returns null if the task could not be located in either bucket.
  Future<String?> markTaskDone(String taskId) async {
    try {
      final now = DateTime.now();
      await _supabase.markTreatmentTaskCompleted(taskId, completedAt: now);

      TreatmentTaskModel? completedTask;
      TreatmentTaskModel? removeFrom(List<TreatmentTaskModel> tasks) {
        final index = tasks.indexWhere((task) => task.id == taskId);
        if (index == -1) return null;
        return tasks.removeAt(index).copyWith(
              status: TaskStatus.completed,
              completedAt: now,
              updatedAt: now,
            );
      }

      completedTask = removeFrom(_todayTasks) ??
          removeFrom(_missedTasks) ??
          removeFrom(_tomorrowTasks) ??
          removeFrom(_upcomingTasks);

      // The same task can appear in both a day bucket and Upcoming. Remove
      // it from every remaining bucket before rebuilding reminders.
      _todayTasks.removeWhere((task) => task.id == taskId);
      _missedTasks.removeWhere((task) => task.id == taskId);
      _tomorrowTasks.removeWhere((task) => task.id == taskId);
      _upcomingTasks.removeWhere((task) => task.id == taskId);
      _pendingTasks.removeWhere((task) => task.id == taskId);
      _bucketTasks(_pendingTasks);

      if (completedTask != null) {
        await _db.upsertRow(
          AppConstants.treatmentTasksTable,
          completedTask.toMap(),
        );
      }

      // Reschedule so the completed task no longer fires reminders.
      await NotificationService.instance.scheduleForTasks(
        _pendingTasks,
        cropNames: _loadedUserId == null
            ? const <String, String>{}
            : await _cropTypesById(_loadedUserId!),
      );
      notifyListeners();

      return completedTask?.cropId;
    } catch (_) {
      return null;
    }
  }

  void clear() {
    _overdueRefreshTimer?.cancel();
    _overdueRefreshTimer = null;
    _notifications = [];
    _locallyDeletedNotificationIds.clear();
    _todayTasks = [];
    _missedTasks = [];
    _tomorrowTasks = [];
    _upcomingTasks = [];
    _pendingTasks = [];
    notifyListeners();
  }
}
