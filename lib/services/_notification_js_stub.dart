// Non-web stub for browser notification interop.
//
// `notification_service.dart` only invokes these on `kIsWeb`, so on mobile
// and desktop builds these are no-ops. Keeping them here lets us avoid
// importing `dart:js` (web-only) from a file that is also compiled for
// Android/iOS/desktop.

void requestPermission() {}

void showNotification(String title, String body) {}
