import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_enums.dart';
import '../data/models/treatment_task_model.dart';
import 'local_notifications_adapter.dart';

/// Schedules grouped morning and 7 PM overdue notifications for pending tasks.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;
  NotificationService._() : _adapter = createLocalNotificationsAdapter();

  @visibleForTesting
  NotificationService.withAdapter(LocalNotificationsAdapter adapter)
      : _adapter = adapter;

  final LocalNotificationsAdapter _adapter;
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
    Map<String, String> cropNames = const <String, String>{},
    bool forceReschedule = false,
  }) async {
    await _adapter.init();
    final prefs = await SharedPreferences.getInstance();
    final playSound = await soundEnabled;
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final tasksByCropAndDay = <String, List<TreatmentTaskModel>>{};
    for (final task in tasks) {
      if (task.isDeleted || task.status != TaskStatus.pending) continue;
      final localDueAt = task.dueAt.toLocal();
      final dueDay =
          DateTime(localDueAt.year, localDueAt.month, localDueAt.day);
      final daysOut = dueDay.difference(todayStart).inDays;
      if (daysOut < 0 || daysOut > 14) continue;
      final key = '${task.cropId}|${_dateKey(dueDay)}';
      tasksByCropAndDay
          .putIfAbsent(key, () => <TreatmentTaskModel>[])
          .add(task);
    }
    const reminderKinds = [ReminderKind.morning, ReminderKind.overdue];
    final desiredScheduleKeys = <String>{
      for (final cropDay in tasksByCropAndDay.keys)
        for (final kind in reminderKinds) '$cropDay|${kind.token}',
    };
    final desiredIds = <int>{
      for (final cropDay in tasksByCropAndDay.keys)
        for (final kind in reminderKinds) reminderIdFor(cropDay, kind.token),
    };
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
    scheduledTasks.removeWhere(
      (scheduleKey, _) => !desiredScheduleKeys.contains(scheduleKey),
    );

    for (final entry in tasksByCropAndDay.entries) {
      final tasksForCropDay = entry.value;
      final firstTask = tasksForCropDay.first;
      final cropId = firstTask.cropId;
      final localDueAt = firstTask.dueAt.toLocal();
      final date = DateTime(localDueAt.year, localDueAt.month, localDueAt.day);
      final taskIds = tasksForCropDay.map((task) => task.id).toList()..sort();
      final cropName = _cropName(cropNames[cropId]);
      final count = tasksForCropDay.length;
      for (final kind in reminderKinds) {
        final when = kind == ReminderKind.morning
            ? DateTime(date.year, date.month, date.day, 4)
            : firstTask.overdueAt;
        // Do not create a late reminder if the app is opened after its time.
        if (!when.isAfter(DateTime.now())) continue;

        final scheduleKey = '${entry.key}|${kind.token}';
        final taskSignature =
            '${taskIds.join(',')}|${_dateKey(date)}|${playSound ? 'sound' : 'quiet'}|${kind.channelId}';
        final alreadyScheduled = scheduledTasks[scheduleKey] == taskSignature;
        final notificationId = reminderIdFor(entry.key, kind.token);
        if (alreadyScheduled &&
            !forceReschedule &&
            pendingIds.contains(notificationId)) {
          continue;
        }
        if (pendingIds.contains(notificationId)) {
          await _adapter.cancel(notificationId);
        }

        final isOverdueReminder = kind == ReminderKind.overdue;
        final title = isOverdueReminder
            ? 'Overdue task${count == 1 ? '' : 's'} for your $cropName crop'
            : count == 1
                ? 'A new task awaits for your $cropName crop'
                : 'New tasks await for your $cropName crop';
        final body = isOverdueReminder
            ? '${count == 1 ? 'A task was' : '$count tasks were'} not completed by 7 PM.'
            : 'Visit your crop now to see ${count == 1 ? "today's task" : "today's tasks"}.';
        await _adapter.schedule(
          id: notificationId,
          when: when,
          title: title,
          body: body,
          kind: kind,
          playSound: playSound,
          payload: 'crop:$cropId',
        );
        scheduledTasks[scheduleKey] = taskSignature;
      }
    }
    await prefs.setString(_scheduledCropTasksKey, jsonEncode(scheduledTasks));
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _cropName(String? value) {
    final name = value?.trim();
    if (name == null || name.isEmpty) return 'crop';
    return name[0].toLowerCase() + name.substring(1);
  }

  // ─── Cancel ───────────────────────────────────────────────────────────────

  Future<void> cancelAll() => _adapter.cancelAll();

  Future<void> cancelForTask(String taskId) async {
    await _adapter.cancel(reminderIdFor(taskId, ReminderKind.due.token));
  }
}
