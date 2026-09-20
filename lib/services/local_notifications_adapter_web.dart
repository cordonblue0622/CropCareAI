import 'dart:async';
import '_notification_js_stub.dart'
    if (dart.library.js) '_notification_js_web.dart' as js;
import 'local_notifications_adapter.dart';

LocalNotificationsAdapter create() => _WebLocalNotificationsAdapter();

class _WebLocalNotificationsAdapter implements LocalNotificationsAdapter {
  final StreamController<String> _tap = StreamController<String>.broadcast();
  final Map<int, Timer> _timers = {};

  @override
  Stream<String> get tapStream => _tap.stream;

  @override
  Future<void> init() async {
    // No-op for web; permission is requested lazily.
  }

  @override
  Future<bool> requestPermission() async {
    try {
      js.requestPermission();
      // The JS bridge does not return a granted/denied result synchronously;
      // assume requested == granted for our scheduling logic.
      return true;
    } catch (_) {
      return false;
    }
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
    final delay = when.difference(DateTime.now());
    if (delay.isNegative) return;
    _timers[id]?.cancel();
    _timers[id] = Timer(delay, () {
      try {
        js.showNotification(title, body);
      } catch (_) {}
      _timers.remove(id);
    });
  }

  @override
  Future<void> cancel(int id) async {
    _timers.remove(id)?.cancel();
  }

  @override
  Future<void> cancelAll() async {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }
}
