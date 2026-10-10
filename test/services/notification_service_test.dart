import 'dart:async';

import 'package:cropcare_ai/core/constants/app_enums.dart';
import 'package:cropcare_ai/data/models/treatment_task_model.dart';
import 'package:cropcare_ai/services/local_notifications_adapter.dart';
import 'package:cropcare_ai/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('schedules a crop-specific overdue notification for 7 PM', () async {
    final adapter = _RecordingNotificationsAdapter();
    final service = NotificationService.withAdapter(adapter);
    final now = DateTime.now();
    final dueAt = DateTime(now.year, now.month, now.day + 1, 10);
    final task = TreatmentTaskModel(
      id: 'task-1',
      treatmentId: 'treatment-1',
      cropId: 'crop-1',
      userId: 'user-1',
      title: 'Water the crop',
      dueAt: dueAt,
      status: TaskStatus.pending,
      createdAt: now,
      updatedAt: now,
    );

    await service.scheduleForTasks([task], cropNames: {'crop-1': 'Tomato'});

    final overdue = adapter.scheduled.singleWhere(
      (reminder) => reminder.kind == ReminderKind.overdue,
    );
    expect(overdue.when, DateTime(dueAt.year, dueAt.month, dueAt.day, 19));
    expect(overdue.title, contains('tomato'));
    expect(overdue.payload, 'crop:crop-1');
    expect(overdue.playSound, isTrue);
  });
}

class _ScheduledReminder {
  final int id;
  final DateTime when;
  final String title;
  final String body;
  final ReminderKind kind;
  final bool playSound;
  final String? payload;

  const _ScheduledReminder({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
    required this.kind,
    required this.playSound,
    this.payload,
  });
}

class _RecordingNotificationsAdapter implements LocalNotificationsAdapter {
  final _tap = StreamController<String>.broadcast();
  final scheduled = <_ScheduledReminder>[];
  final pendingIds = <int>{};

  @override
  Stream<String> get tapStream => _tap.stream;

  @override
  Future<void> init() async {}

  @override
  Future<String?> getLaunchPayload() async => null;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required ReminderKind kind,
    required bool playSound,
    String? payload,
  }) async {
    scheduled.add(
      _ScheduledReminder(
        id: id,
        when: when,
        title: title,
        body: body,
        kind: kind,
        playSound: playSound,
        payload: payload,
      ),
    );
    pendingIds.add(id);
  }

  @override
  Future<void> cancel(int id) async {
    pendingIds.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    pendingIds.clear();
  }

  @override
  Future<Set<int>> pendingNotificationIds() async => pendingIds;
}
