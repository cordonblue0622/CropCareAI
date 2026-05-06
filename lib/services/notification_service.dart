import 'dart:async';
import 'package:flutter/foundation.dart';

import '../data/models/treatment_task_model.dart';
import '_notification_js_stub.dart'
    if (dart.library.js) '_notification_js_web.dart' as js;

/// Schedules browser Notification API reminders for treatment tasks.
///
/// Three reminder points per task (all silently skipped if the time is past):
///   1. 30 minutes before [TreatmentTaskModel.dueAt]
///   2. Exactly at [TreatmentTaskModel.dueAt]
///   3. 8 PM end-of-day if the task is still on today's schedule and no
///      update has been received (caller decides whether to cancel by
///      calling [cancelAll] + [scheduleForTasks] with the updated list).
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;

  NotificationService._();

  final List<Timer> _timers = [];

  // ─── Permission ───────────────────────────────────────────────────────────

  /// Ask the browser for notification permission (no-op on non-web).
  void requestPermission() {
    if (!kIsWeb) return;
    try {
      js.requestPermission();
    } catch (_) {}
  }

  // ─── Scheduling ───────────────────────────────────────────────────────────

  /// Cancel all pending timers and schedule new ones for [tasks].
  void scheduleForTasks(List<TreatmentTaskModel> tasks) {
    cancelAll();
    if (!kIsWeb) return;
    final now = DateTime.now();
    for (final task in tasks) {
      _scheduleSingle(task, now);
    }
  }

  void _scheduleSingle(TreatmentTaskModel task, DateTime now) {
    final dueAt = task.dueAt;
    final title = task.title;

    // 1. 30-minute warning
    final thirtyBefore = dueAt.subtract(const Duration(minutes: 30));
    if (thirtyBefore.isAfter(now)) {
      _timers.add(Timer(thirtyBefore.difference(now), () {
        _show(
          'Upcoming Task — 30 min',
          '"$title" is due in 30 minutes. Get ready!',
        );
      }));
    }

    // 2. At due time
    if (dueAt.isAfter(now)) {
      _timers.add(Timer(dueAt.difference(now), () {
        _show(
          'Task Due Now',
          '"$title" is due. Complete it and log your progress.',
        );
      }));
    }

    // 3. End-of-day reminder at 8 PM (only for today's tasks)
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(dueAt.year, dueAt.month, dueAt.day);
    if (dueDay == today) {
      final eod = DateTime(now.year, now.month, now.day, 20, 0);
      if (eod.isAfter(now)) {
        _timers.add(Timer(eod.difference(now), () {
          _show(
            'Pending Task — No Update Yet',
            '"$title" still has no recorded update for today. Log your progress to keep treatments on track.',
          );
        }));
      }
    }
  }

  // ─── Cancel ───────────────────────────────────────────────────────────────

  void cancelAll() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  void _show(String title, String body) {
    if (!kIsWeb) return;
    try {
      js.showNotification(title, body);
    } catch (_) {}
  }
}
