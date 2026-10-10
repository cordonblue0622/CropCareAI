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
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _tap.add(payload);
        }
      },
    );

    // Create the notification channels up-front so sound behavior is stable.
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      for (final kind in ReminderKind.values) {
        await androidImpl.createNotificationChannel(
          AndroidNotificationChannel(
            '${kind.channelId}_sound',
            kind.channelName,
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );
        await androidImpl.createNotificationChannel(
          AndroidNotificationChannel(
            '${kind.channelId}_quiet',
            '${kind.channelName} (quiet)',
            importance: Importance.high,
            playSound: false,
            enableVibration: false,
          ),
        );
      }
    }

    _initialized = true;
  }

  @override
  Future<String?> getLaunchPayload() async {
    await init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    final payload = details?.notificationResponse?.payload;
    return details?.didNotificationLaunchApp == true &&
            payload != null &&
            payload.isNotEmpty
        ? payload
        : null;
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    if (Platform.isAndroid) {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidImpl?.requestNotificationsPermission();
      return granted ?? false;
    }
    if (Platform.isIOS) {
      final iosImpl = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await iosImpl?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return false;
  }

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
    await init();
    final scheduledTz = tz.TZDateTime.from(when, tz.local);
    if (!scheduledTz.isAfter(tz.TZDateTime.now(tz.local))) {
      // Past times silently skipped — caller decides whether to fire-now.
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      '${kind.channelId}_${playSound ? 'sound' : 'quiet'}',
      '${kind.channelName}${playSound ? '' : ' (quiet)'}',
      importance: Importance.high,
      priority: Priority.high,
      playSound: playSound,
      enableVibration: playSound,
    );

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTz,
        NotificationDetails(
          android: androidDetails,
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: playSound,
          ),
        ),
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
        NotificationDetails(
          android: androidDetails,
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: playSound,
          ),
        ),
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

  @override
  Future<Set<int>> pendingNotificationIds() async {
    await init();
    final requests = await _plugin.pendingNotificationRequests();
    return requests.map((request) => request.id).toSet();
  }
}
