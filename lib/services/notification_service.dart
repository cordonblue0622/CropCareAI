import 'dart:async';

import '../data/models/treatment_task_model.dart';
import 'local_notifications_adapter.dart';

/// Schedules treatment-task reminders via the platform-specific
/// [LocalNotificationsAdapter]. Three reminder points per task:
///
///   1. [ReminderKind.thirtyMin]  — `dueAt - 30min`
///   2. [ReminderKind.due]        — at `dueAt`
///   3. [ReminderKind.overdue]    — `dueAt + 4h` (skipped if task completed)
///
/// Past-due reminders are silently skipped by the adapter.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;
  NotificationService._();

  final LocalNotificationsAdapter _adapter = createLocalNotificationsAdapter();

  Stream<String> get tapStream => _adapter.tapStream;

  // ─── Permission ───────────────────────────────────────────────────────────

  Future<bool> requestPermission() => _adapter.requestPermission();

  // ─── Scheduling ───────────────────────────────────────────────────────────

  /// Cancel everything currently scheduled and replace with reminders for
  /// the given [tasks]. Idempotent — safe to call repeatedly.
  Future<void> scheduleForTasks(List<TreatmentTaskModel> tasks) async {
    await _adapter.init();
    await _adapter.cancelAll();
    for (final task in tasks) {
      await _scheduleSingle(task);
    }
  }

  Future<void> _scheduleSingle(TreatmentTaskModel task) async {
    final dueAt = task.dueAt;
    final title = task.title;
    final payload = 'task:${task.id}';

    await _adapter.schedule(
      id: reminderIdFor(task.id, ReminderKind.thirtyMin.token),
      when: dueAt.subtract(const Duration(minutes: 30)),
      title: 'Upcoming Task — 30 min',
      body: '"$title" is due in 30 minutes. Get ready!',
      kind: ReminderKind.thirtyMin,
      payload: payload,
    );

    await _adapter.schedule(
      id: reminderIdFor(task.id, ReminderKind.due.token),
      when: dueAt,
      title: 'Task Due Now',
      body: '"$title" is due. Complete it and log your progress.',
      kind: ReminderKind.due,
      payload: payload,
    );

    await _adapter.schedule(
      id: reminderIdFor(task.id, ReminderKind.overdue.token),
      when: dueAt.add(const Duration(hours: 4)),
      title: 'Task Overdue',
      body: '"$title" is overdue. Mark it done or reschedule.',
      kind: ReminderKind.overdue,
      payload: payload,
    );
  }

  // ─── Cancel ───────────────────────────────────────────────────────────────

  Future<void> cancelAll() => _adapter.cancelAll();

  Future<void> cancelForTask(String taskId) async {
    await _adapter.cancel(reminderIdFor(taskId, ReminderKind.thirtyMin.token));
    await _adapter.cancel(reminderIdFor(taskId, ReminderKind.due.token));
    await _adapter.cancel(reminderIdFor(taskId, ReminderKind.overdue.token));
  }
}
