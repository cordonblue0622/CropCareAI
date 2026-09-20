import 'dart:async';

// Conditional import: use _io implementation on mobile/desktop, _web on web.
// `dart.library.js` chosen to match the existing pattern in
// notification_service.dart (which uses the same library check).
import 'local_notifications_adapter_io.dart'
    if (dart.library.js) 'local_notifications_adapter_web.dart' as impl;

/// Three reminder kinds per task. Used as channel ids on Android and as
/// a discriminator inside [reminderIdFor].
enum ReminderKind { thirtyMin, due, overdue }

extension ReminderKindX on ReminderKind {
  String get token => switch (this) {
        ReminderKind.thirtyMin => '30min',
        ReminderKind.due => 'due',
        ReminderKind.overdue => 'overdue',
      };

  String get channelId => switch (this) {
        ReminderKind.thirtyMin => 'task_30min',
        ReminderKind.due => 'task_due',
        ReminderKind.overdue => 'task_overdue',
      };

  String get channelName => switch (this) {
        ReminderKind.thirtyMin => '30-minute task warning',
        ReminderKind.due => 'Task due reminders',
        ReminderKind.overdue => 'Overdue task reminders',
      };
}

/// Cross-platform local-notification scheduling.
///
/// All calls are no-ops if the platform implementation cannot deliver
/// (e.g. permission denied) — they never throw to callers.
abstract class LocalNotificationsAdapter {
  /// Initialise the platform implementation. Safe to call multiple times.
  Future<void> init();

  /// Request OS permission to display notifications.
  /// Returns `true` if granted (or already granted), `false` if denied.
  Future<bool> requestPermission();

  /// Schedule one notification.
  Future<void> schedule({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required ReminderKind kind,
    required bool playSound,
    String? payload,
  });

  /// Cancel a previously scheduled notification by id.
  Future<void> cancel(int id);

  /// Cancel everything we have scheduled.
  Future<void> cancelAll();

  /// Stream of payloads delivered when the user taps a notification.
  /// Empty broadcast stream on platforms where tap-handling is not wired.
  Stream<String> get tapStream;
}

/// Build the singleton adapter for the current platform.
LocalNotificationsAdapter createLocalNotificationsAdapter() => impl.create();

/// Deterministic 32-bit non-negative reminder id for a (taskId, kind) pair.
///
/// `flutter_local_notifications` requires a 32-bit signed int. We pack the
/// reminder kind into the low 2 bits and a 30-bit hash of the task id into
/// the high bits, so the same task+kind always resolves to the same id and
/// distinct (task, kind) tuples almost never collide.
int reminderIdFor(String taskId, String kind) {
  // Use 29 bits of hash so that after the 2-bit left-shift the result fits
  // in a 31-bit non-negative signed int (max 0x7FFFFFFF).
  final base = taskId.hashCode & 0x1FFFFFFF; // 29 bits, always non-negative
  final suffix = switch (kind) {
    '30min' => 0,
    'due' => 1,
    'overdue' => 2,
    _ => 3,
  };
  return (base << 2) | suffix;
}
