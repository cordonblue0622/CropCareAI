import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_enums.dart';
import '../data/models/treatment_task_model.dart';
import 'local_notifications_adapter.dart';

/// Schedules one generic crop-attention notification at the nearest pending
/// task for each crop, avoiding a stream of notifications for individual tasks.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;
  NotificationService._();

  final LocalNotificationsAdapter _adapter = createLocalNotificationsAdapter();
  static const _soundPreferenceKey = 'notification_sound_enabled';
  static const _scheduledCropTasksKey = 'notification_scheduled_crop_tasks';

  Stream<String> get tapStream => _adapter.tapStream;

  Future<String?> initializeAndGetLaunchPayload() async {
    await _adapter.init();
    return _adapter.getLaunchPayload();
  }

  Future<bool> get soundEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_soundPreferenceKey) ?? true;
  }

  Future<void> setSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundPreferenceKey, enabled);
  }

  // ─── Permission ───────────────────────────────────────────────────────────

  Future<bool> requestPermission() => _adapter.requestPermission();

  // ─── Scheduling ───────────────────────────────────────────────────────────

  /// Cancel everything currently scheduled and replace with reminders for
  /// the given [tasks]. Idempotent — safe to call repeatedly.
  Future<void> scheduleForTasks(
    List<TreatmentTaskModel> tasks, {
    bool forceReschedule = false,
  }) async {
    await _adapter.init();
    final prefs = await SharedPreferences.getInstance();
    final playSound = await soundEnabled;
    final nextTaskByCrop = <String, TreatmentTaskModel>{};
    for (final task in tasks) {
      if (task.isDeleted || task.status != TaskStatus.pending) continue;
      final current = nextTaskByCrop[task.cropId];
      if (current == null || task.dueAt.isBefore(current.dueAt)) {
        nextTaskByCrop[task.cropId] = task;
      }
    }
    final desiredIds = nextTaskByCrop.keys
        .map((cropId) => reminderIdFor(cropId, ReminderKind.due.token))
        .toSet();
    final pendingIds = await _adapter.pendingNotificationIds();
    for (final staleId in pendingIds.difference(desiredIds)) {
      await _adapter.cancel(staleId);
    }

    final scheduledTasks = <String, String>{
      for (final entry
          in (jsonDecode(prefs.getString(_scheduledCropTasksKey) ?? '{}')
                  as Map<String, dynamic>)
              .entries)
        entry.key: entry.value.toString(),
    };
    scheduledTasks
        .removeWhere((cropId, _) => !nextTaskByCrop.containsKey(cropId));

    for (final task in nextTaskByCrop.values) {
      final scheduleKey =
          '${task.id}|${task.dueAt.toIso8601String()}|${playSound ? 'sound' : 'quiet'}';
      final alreadyScheduled = scheduledTasks[task.cropId] == scheduleKey;
      final notificationId = reminderIdFor(task.cropId, ReminderKind.due.token);
      final overdue = task.dueAt.isBefore(DateTime.now());
      if (alreadyScheduled &&
          (overdue ||
              (!forceReschedule && pendingIds.contains(notificationId)))) {
        continue;
      }
      if (forceReschedule && pendingIds.contains(notificationId) && !overdue) {
        await _adapter.cancel(notificationId);
      }
      final scheduled =
          await _scheduleCropAttention(task, playSound: playSound);
      if (scheduled) scheduledTasks[task.cropId] = scheduleKey;
    }
    await prefs.setString(_scheduledCropTasksKey, jsonEncode(scheduledTasks));
  }

  Future<bool> _scheduleCropAttention(
    TreatmentTaskModel task, {
    required bool playSound,
  }) async {
    final overdue = task.dueAt.isBefore(DateTime.now());
    final id = reminderIdFor(task.cropId, ReminderKind.due.token);
    if (overdue && (await _adapter.pendingNotificationIds()).contains(id)) {
      return true;
    }
    await _adapter.schedule(
      id: id,
      when: overdue
          ? DateTime.now().add(const Duration(seconds: 20))
          : task.dueAt,
      title: 'Your crop needs attention',
      body: 'Visit CropCare AI to see what needs attention.',
      kind: overdue ? ReminderKind.overdue : ReminderKind.due,
      playSound: playSound,
      payload: 'crop:${task.cropId}',
    );
    return true;
  }

  // ─── Cancel ───────────────────────────────────────────────────────────────

  Future<void> cancelAll() => _adapter.cancelAll();

  Future<void> cancelForTask(String taskId) async {
    await _adapter.cancel(reminderIdFor(taskId, ReminderKind.due.token));
  }
}
