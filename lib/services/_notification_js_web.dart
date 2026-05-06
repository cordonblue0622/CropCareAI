// Web implementation of browser notification interop.
//
// Bridges to the `cropCareRequestNotificationPermission` and
// `cropCareShowNotification` JS helpers defined in `web/index.html`.

// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

void requestPermission() {
  try {
    js.context.callMethod('cropCareRequestNotificationPermission', []);
  } catch (_) {}
}

void showNotification(String title, String body) {
  try {
    js.context.callMethod('cropCareShowNotification', [title, body]);
  } catch (_) {}
}
