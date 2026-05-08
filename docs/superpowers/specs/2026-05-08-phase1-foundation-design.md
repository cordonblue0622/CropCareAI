# Phase 1 — Foundation & Quick Wins (Days 1–2)

**Status:** Approved design.
**Context:** Thesis defense in <2 weeks. Android phone is the primary demo target. This is the first phase of a four-phase roadmap; subsequent phases (Calendar+Graph+Notifications, Video+Offline diagnosis, Polish) get their own spec → plan → implement cycles.

## Constraints

- **No Supabase schema changes.** Work only within the existing schema (the working developer is helping classmates and has read-only access to the codebase, no DB admin access).
- **No `.env` work needed.** Supabase URL + anon key are already hardcoded in [lib/core/constants/app_constants.dart](../../../lib/core/constants/app_constants.dart). Run with a freshly registered test account.
- **Android-primary, web fallback.** No iOS work in this phase.
- **No FCM / push notifications.** Local notifications only (covered by `flutter_local_notifications`).
- **Defensive remote calls** — keep using the `_runOrFallback` pattern already in the codebase so missing remote data degrades to local SQLite.

## Goal

Three small deliverables that unblock Phase 2 and ship visible polish:

1. Disease-label humanization across diagnosis-display surfaces.
2. Cross-platform local-notification adapter with an Android implementation.
3. Verified offline photo-diagnosis pipeline on Android.

## 1.1 Disease Label Humanization

### Problem
Raw model labels (e.g. `tomato_bacterial_spot`, `tomato_early_blight`) leak into UI surfaces — Disease Library, Scan Result, Diagnosis History.

### Design
Add a single pure helper in a new file `lib/core/utils/label_formatter.dart` (keeps the model file focused on data shape):

```dart
String humanizeDiseaseLabel(String raw) {
  // 'tomato_bacterial_spot' → 'Tomato Bacterial Spot'
  // 'healthy' → 'Healthy'
  // Idempotent: already-formatted strings pass through.
  if (raw.isEmpty) return raw;
  return raw
      .split(RegExp(r'[_\s]+'))
      .where((token) => token.isNotEmpty)
      .map((t) => t[0].toUpperCase() + t.substring(1).toLowerCase())
      .join(' ');
}
```

### Application points (display layer only — model values stay machine-readable so TFLite mapping keeps working)
- [lib/features/library/library_screen.dart](../../../lib/features/library/library_screen.dart) — disease cards
- [lib/features/scan/scan_result_screen.dart](../../../lib/features/scan/scan_result_screen.dart) — diagnosis result heading
- [lib/features/scan/diagnostic_history_screen.dart](../../../lib/features/scan/diagnostic_history_screen.dart) — history rows
- Any place `DiagnosisModel.detectedDiseaseName` or `DiseaseKnowledgeModel.diseaseName` is rendered as `Text(...)`.

### Testing
Unit test in `test/utils/label_formatter_test.dart` covering:
- snake_case → Title Case
- already-humanized passthrough
- empty string
- single token
- multiple underscores / mixed whitespace

## 1.2 Cross-Platform Local Notification Adapter

### Problem
[lib/services/notification_service.dart](../../../lib/services/notification_service.dart) is web-only — it uses `dart:js` via the `_notification_js_*` files and falls back to `Timer`s that don't survive app suspension on mobile. For an Android demo, this is unusable.

### Design

**Package:** Add `flutter_local_notifications: ^17.2.3` (latest stable for Flutter SDK >=3.2). Also add `timezone: ^0.9.4` (peer dep used for `zonedSchedule`).

**New abstraction** — `lib/services/local_notifications_adapter.dart`:

```dart
abstract class LocalNotificationsAdapter {
  Future<void> init();
  Future<bool> requestPermission();
  Future<void> schedule({
    required int id,            // deterministic hash of taskId+reminderType
    required DateTime when,
    required String title,
    required String body,
    required String channelId,  // 'task_30min' | 'task_due' | 'task_overdue'
    String? payload,            // e.g. 'crop:<cropId>:date:<yyyy-MM-dd>'
  });
  Future<void> cancel(int id);
  Future<void> cancelAll();
  Stream<String> get tapStream; // emits payloads when user taps notification
}
```

**Conditional import** mirroring the existing `_notification_js_stub.dart` / `_notification_js_web.dart` pattern in this codebase (uses `dart.library.js`, not `dart.library.html`, to match what `notification_service.dart` already does):

```dart
// in local_notifications_adapter.dart
import 'local_notifications_adapter_io.dart'
    if (dart.library.js) 'local_notifications_adapter_web.dart' as impl;

LocalNotificationsAdapter createAdapter() => impl.create();
```

**Two implementations:**

- `local_notifications_adapter_io.dart` — uses `flutter_local_notifications` for Android (and is a no-op on iOS for this phase). Three Android channels created in `init()`:
  - `task_30min` (importance HIGH, vibration on)
  - `task_due` (importance HIGH, vibration + sound)
  - `task_overdue` (importance DEFAULT, no vibration — less aggressive nag)
  Uses `zonedSchedule` with `androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle`. Tap responses get pumped onto `tapStream` via the package's `onDidReceiveNotificationResponse` callback.

- `local_notifications_adapter_web.dart` — delegates to existing JS bridge ([lib/services/_notification_js_web.dart](../../../lib/services/_notification_js_web.dart)). `schedule` becomes a `Timer` (current behavior, keeps web parity). `tapStream` emits an empty broadcast stream — clicking a web notification just dismisses.

**`NotificationService` becomes orchestrator only.** Same public API (`scheduleForTasks`, `cancelAll`, `requestPermission`) so [lib/features/notifications/providers/notifications_provider.dart](../../../lib/features/notifications/providers/notifications_provider.dart) doesn't need to change. Internals route every call through `LocalNotificationsAdapter` — no more `kIsWeb` branching at call sites; the adapter handles platform differences.

**Reminder ID hashing:** stable so reschedule cancels the right ones.

```dart
int reminderIdFor(String taskId, String type /* '30min' | 'due' | 'overdue' */) {
  // Combine taskId hash with a 2-bit suffix; fits in 32-bit signed int the package wants.
  final base = taskId.hashCode & 0x3FFFFFFF; // 30 bits
  final suffix = switch (type) { '30min' => 0, 'due' => 1, 'overdue' => 2, _ => 3 };
  return (base << 2) | suffix;
}
```

### Reminder schedule per task

| Reminder | When | Channel |
|---|---|---|
| 30-min warning | `dueAt - 30min` | `task_30min` |
| At due | `dueAt` | `task_due` |
| Overdue nag | `dueAt + 4h`, only if still pending | `task_overdue` |

(The current code's "8 PM end-of-day" reminder is replaced by the `+4h` overdue nag — more predictable and less awkward when due times are spread across the day.)

Past times silently skip (`zonedSchedule` would throw — we guard).

### `AndroidManifest.xml` updates ([android/app/src/main/AndroidManifest.xml](../../../android/app/src/main/AndroidManifest.xml))

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.VIBRATE"/>

<receiver android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
<receiver android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
  <intent-filter>
    <action android:name="android.intent.action.BOOT_COMPLETED"/>
    <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
    <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
  </intent-filter>
</receiver>
```

### Permission flow
- Call `requestPermission()` once on first reach of the Notifications screen / Crop Detail Progress tab (already happens in `NotificationsProvider.fetchAll`).
- On Android 13+ this triggers the runtime `POST_NOTIFICATIONS` system dialog.
- On Android 12+ for exact alarms, `flutter_local_notifications` will fall back to inexact scheduling if the user denies — log a debug warning, don't block the feature.

### Testing
- Unit tests for `reminderIdFor` (deterministic, distinct across types, fits in 32-bit signed).
- Manual smoke test on Android device:
  1. Register test account, create a crop, add a treatment task due 31 minutes from now.
  2. Confirm 30-min reminder fires within 60 seconds.
  3. Confirm at-due reminder fires.
  4. Mark task complete before +4h, confirm overdue reminder is cancelled (no notification).
  5. Reboot phone, confirm pending reminder still fires (validates `BOOT_COMPLETED` receiver).

## 1.3 Verify Offline Photo Diagnosis on Android

### Problem
Offline pipeline exists on paper ([lib/services/local_classifier_service_io.dart](../../../lib/services/local_classifier_service_io.dart), `tflite_classifier_core.dart`, disease KB seeded in commit `e6c4152`). Status on a real Android device with airplane mode is unverified.

### Scope (this phase)
Only **verify and fix any breakage**. No architecture changes, no new offline features (those are Phase 3).

### Verification checklist
On a fresh Android install with the test account:
1. Online, create one crop and verify a normal scan diagnosis works (baseline).
2. Toggle airplane mode on.
3. Run a scan from Scan tab → confirm:
   - Camera capture works.
   - Local TFLite classifier produces a top-1 label + confidence ≥ `temporaryScannerMinConfidence` (0.45).
   - Disease KB lookup returns a row with treatment recommendations from local SQLite (`disease_knowledge_base` table seeded by [lib/features/library/library_screen.dart](../../../lib/features/library/library_screen.dart) import flow or factory data).
   - `DiagnosisModel` is written to local SQLite via `DatabaseHelper.upsertRow`.
   - Result screen renders disease name + treatment recommendation without errors.
4. Toggle airplane mode off, verify the diagnosis appears in Diagnosis History and (eventually) syncs to Supabase via `sync_service`.

### Likely fixes (don't pre-emptively code; address only if found)
- TFLite asset path mismatch under release builds vs. debug.
- `DiseaseKnowledgeRepository` falling back to remote when offline (should hit local cache first).
- Image preprocessing differences between local-classifier path and remote-classifier path producing different label probabilities.

If the smoke test passes clean, this becomes a 30-min task instead of a full day — gives buffer back to Phase 2.

## Out of scope for Phase 1

- iOS notification setup (`AppDelegate.swift`, `UNUserNotificationCenter`).
- FCM / Firebase push.
- Notification deep-linking into specific calendar dates (Phase 2 — calendar UI doesn't exist yet).
- Health-score recomputation hooks (Phase 2).
- Disease-label *editing* UI in the library (out of thesis scope).

## Definition of Done

- [ ] `humanizeDiseaseLabel` exists, has unit tests, and is applied to the four display surfaces listed above.
- [ ] `flutter_local_notifications` + `timezone` added to `pubspec.yaml`, `pubspec.lock` regenerated.
- [ ] `LocalNotificationsAdapter` with `_io` (Android) and `_web` implementations exists and replaces the direct `Timer`/JS-bridge calls inside `NotificationService`.
- [ ] `AndroidManifest.xml` has the six permissions + two receivers from §1.2.
- [ ] `reminderIdFor` unit tests pass.
- [ ] Manual on-device test (steps 1–5 in §1.2 testing) passes on at least one Android phone (API 30+).
- [ ] Manual offline-photo-diagnosis test (steps 1–4 in §1.3) passes on the same device.
- [ ] No regression on web — opening the app in Chrome still schedules browser notifications via the existing JS bridge.

## Files this phase will touch

**New:**
- `lib/core/utils/label_formatter.dart`
- `lib/services/local_notifications_adapter.dart`
- `lib/services/local_notifications_adapter_io.dart`
- `lib/services/local_notifications_adapter_web.dart`
- `test/utils/label_formatter_test.dart`
- `test/services/local_notifications_adapter_test.dart` (just for `reminderIdFor`)

**Modified:**
- `pubspec.yaml`
- `lib/services/notification_service.dart`
- `lib/features/library/library_screen.dart`
- `lib/features/scan/scan_result_screen.dart`
- `lib/features/scan/diagnostic_history_screen.dart`
- `android/app/src/main/AndroidManifest.xml`
