import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'local_notifications_adapter.dart';

LocalNotificationsAdapter create() => _IoLocalNotificationsAdapter();

class _IoLocalNotificationsAdapter implements LocalNotificationsAdapter {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _tap = StreamController<String>.broadcast();
  bool _initialized = false;

  @override
  Stream<String> get tapStream => _tap.stream;

  @override
  Future<void> init() async {
    if (_initialized) return;

    tzdata.initializeTimeZones();
    // Best-effort local zone detection. If unknown, fall back to UTC; the
    // package will still fire reminders, just with whatever zone is set.
    try {
      tz.setLocalLocation(tz.getLocation(DateTime.now().timeZoneName));
    } catch (e) {
      // IANA lookup typically fails when DateTime.now().timeZoneName is an
      // abbreviation (e.g. "PHT", "PST"). UTC fallback is safe for one-off
      // zonedSchedule because TZDateTime.from preserves the absolute moment;
      // wall-clock firing time on the user's device remains correct.
      debugPrint('NotificationsAdapter: tz fallback to UTC ($e)');
      tz.setLocalLocation(tz.UTC);
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _tap.add(payload);
        }
      },
    );

    // Create the three notification channels up-front.
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      for (final kind in ReminderKind.values) {
        await androidImpl.createNotificationChannel(
          AndroidNotificationChannel(
            kind.channelId,
            kind.channelName,
            importance: kind == ReminderKind.overdue
                ? Importance.defaultImportance
                : Importance.high,
            playSound: kind != ReminderKind.overdue,
            enableVibration: kind != ReminderKind.overdue,
          ),
        );
      }
    }

    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    if (!Platform.isAndroid) return false;
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl == null) return false;
    final granted = await androidImpl.requestNotificationsPermission();
    return granted ?? false;
  }

  @override
  Future<void> schedule({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required ReminderKind kind,
    String? payload,
  }) async {
    await init();
    final scheduledTz = tz.TZDateTime.from(when, tz.local);
    if (!scheduledTz.isAfter(tz.TZDateTime.now(tz.local))) {
      // Past times silently skipped — caller decides whether to fire-now.
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      kind.channelId,
      kind.channelName,
      importance: kind == ReminderKind.overdue
          ? Importance.defaultImportance
          : Importance.high,
      priority: Priority.high,
      playSound: kind != ReminderKind.overdue,
      enableVibration: kind != ReminderKind.overdue,
    );

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTz,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } on PlatformException catch (e) {
      // SCHEDULE_EXACT_ALARM not granted on Android 12+ is the expected case;
      // logged so other platform errors are visible for diagnostics.
      debugPrint(
          'NotificationsAdapter: exact-alarm schedule failed, retrying inexact ($e)');
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTz,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  @override
  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id);
  }

  @override
  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}
