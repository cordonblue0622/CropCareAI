import 'package:flutter/foundation.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_enums.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/models/notification_model.dart';
import '../../../data/models/treatment_task_model.dart';
import '../../../data/remote/supabase_service.dart';
import '../../../services/notification_service.dart';

class NotificationsProvider extends ChangeNotifier {
  final SupabaseService _supabase;
  final DatabaseHelper _db;

  List<NotificationModel> _notifications = [];
  List<TreatmentTaskModel> _todayTasks = [];
  List<TreatmentTaskModel> _missedTasks = [];
  bool _isLoading = false;

  NotificationsProvider(
      {required SupabaseService supabase, required DatabaseHelper db})
      : _supabase = supabase,
        _db = db;

  List<NotificationModel> get notifications => _notifications;
  List<NotificationModel> get unread =>
      _notifications.where((n) => !n.isRead).toList();
  List<TreatmentTaskModel> get todayTasks => _todayTasks;
  List<TreatmentTaskModel> get missedTasks => _missedTasks;
  bool get isLoading => _isLoading;
  int get unreadCount => unread.length;

  // ─── Fetch ────────────────────────────────────────────────────────────────

  Future<void> fetchAll(String userId) async {
    _isLoading = true;
    notifyListeners();

    await Future.wait([
      _fetchNotifications(userId),
      _fetchTasks(userId),
    ]);

    _isLoading = false;
    notifyListeners();

    // Schedule browser notifications for today's pending tasks.
    // ignore: discarded_futures
    NotificationService.instance.requestPermission();
    // ignore: discarded_futures
    NotificationService.instance.scheduleForTasks(_todayTasks);
  }

  Future<void> _fetchNotifications(String userId) async {
    try {
      final rows = await _supabase.getNotifications(userId);
      _notifications = rows.map(NotificationModel.fromMap).toList();
      await _db.upsertRows(
        AppConstants.notificationsTable,
        _notifications.map((notification) => notification.toMap()),
      );
    } catch (_) {
      final rows =
          await _db.queryByUserId(AppConstants.notificationsTable, userId, includeDeleted: true);
      _notifications = rows.map(NotificationModel.fromMap).toList();
    }
  }

  Future<void> _fetchTasks(String userId) async {
    try {
      final rows = await _supabase.getTreatmentTasksByUser(userId);
      final allTasks = rows.map(TreatmentTaskModel.fromMap).toList();
      await _db.upsertRows(
        AppConstants.treatmentTasksTable,
        allTasks.map((task) => task.toMap()),
      );
      _bucketTasks(allTasks);
    } catch (_) {
      final rows = await _db.queryByUserId(AppConstants.treatmentTasksTable, userId);
      final allTasks = rows.map(TreatmentTaskModel.fromMap).toList();
      _bucketTasks(allTasks);
    }
  }

  void _bucketTasks(List<TreatmentTaskModel> allTasks) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    _todayTasks = allTasks
        .where((task) =>
            !task.dueAt.isBefore(todayStart) &&
            task.dueAt.isBefore(todayEnd) &&
            task.status == TaskStatus.pending)
        .toList();

    _missedTasks = allTasks
        .where((task) =>
            task.dueAt.isBefore(todayStart) &&
            task.status == TaskStatus.pending)
        .toList();
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> markRead(String notificationId) async {
    try {
      await _supabase.markNotificationRead(notificationId);
      final idx = _notifications.indexWhere((n) => n.id == notificationId);
      if (idx != -1) {
        final updated = _notifications[idx].copyWith(isRead: true);
        _notifications[idx] = updated;
        await _db.upsertRow(AppConstants.notificationsTable, updated.toMap());
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> markTaskDone(String taskId) async {
    try {
      final now = DateTime.now();
      await _supabase.markTreatmentTaskCompleted(taskId, completedAt: now);

      TreatmentTaskModel? completedTask;
      final todayIdx = _todayTasks.indexWhere((task) => task.id == taskId);
      if (todayIdx != -1) {
        completedTask = _todayTasks.removeAt(todayIdx).copyWith(
              status: TaskStatus.completed,
              completedAt: now,
              updatedAt: now,
            );
      }

      final missedIdx = _missedTasks.indexWhere((task) => task.id == taskId);
      if (missedIdx != -1) {
        completedTask = _missedTasks.removeAt(missedIdx).copyWith(
              status: TaskStatus.completed,
              completedAt: now,
              updatedAt: now,
            );
      }

      if (completedTask != null) {
        await _db.upsertRow(
          AppConstants.treatmentTasksTable,
          completedTask.toMap(),
        );
      }

      // Reschedule so the completed task no longer fires reminders.
      // ignore: discarded_futures
      NotificationService.instance.scheduleForTasks(_todayTasks);
      notifyListeners();
    } catch (_) {}
  }

  void clear() {
    _notifications = [];
    _todayTasks = [];
    _missedTasks = [];
    notifyListeners();
  }
}
