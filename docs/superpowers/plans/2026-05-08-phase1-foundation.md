# Phase 1 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **DO NOT auto-commit.** The repo owner reviews and commits manually. Every "stage for review" step says exactly that — leave changes unstaged or `git add` only, never `git commit`. This rule overrides any default workflow step in any skill.

**Goal:** Land three foundation deliverables for the CropCare AI thesis demo: (1) human-readable disease labels across all display surfaces, (2) a cross-platform local-notification adapter with an Android implementation via `flutter_local_notifications`, and (3) verified offline photo diagnosis on Android.

**Architecture:** A pure helper `humanizeDiseaseLabel` lives in `lib/core/utils/label_formatter.dart` and is called at every display site (model fields stay machine-readable). A new `LocalNotificationsAdapter` interface routes scheduling calls to platform-specific implementations (`_io.dart` for Android via `flutter_local_notifications`, `_web.dart` delegating to the existing JS bridge), selected via conditional import using `dart.library.js` to match the existing pattern. `NotificationService` becomes a thin orchestrator over the adapter, preserving its current public API.

**Tech Stack:** Flutter SDK >=3.2, Dart 3.x, Provider state-mgmt, sqflite, Supabase (no schema changes), `flutter_local_notifications: ^17.2.3`, `timezone: ^0.9.4`, existing `flutter_test`.

**Spec:** [docs/superpowers/specs/2026-05-08-phase1-foundation-design.md](../specs/2026-05-08-phase1-foundation-design.md)

---

## Task 1: Add `humanizeDiseaseLabel` helper with unit tests

**Files:**
- Create: `lib/core/utils/label_formatter.dart`
- Test: `test/utils/label_formatter_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/utils/label_formatter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cropcare_ai/core/utils/label_formatter.dart';

void main() {
  group('humanizeDiseaseLabel', () {
    test('converts snake_case to Title Case', () {
      expect(humanizeDiseaseLabel('tomato_bacterial_spot'),
          'Tomato Bacterial Spot');
      expect(humanizeDiseaseLabel('tomato_early_blight'),
          'Tomato Early Blight');
      expect(humanizeDiseaseLabel('pepper_bell_healthy'),
          'Pepper Bell Healthy');
    });

    test('handles single token', () {
      expect(humanizeDiseaseLabel('healthy'), 'Healthy');
      expect(humanizeDiseaseLabel('TOMATO'), 'Tomato');
    });

    test('is idempotent on already-humanized strings', () {
      expect(humanizeDiseaseLabel('Tomato Bacterial Spot'),
          'Tomato Bacterial Spot');
    });

    test('collapses multiple separators', () {
      expect(humanizeDiseaseLabel('tomato___bacterial  spot'),
          'Tomato Bacterial Spot');
    });

    test('returns empty for empty input', () {
      expect(humanizeDiseaseLabel(''), '');
    });

    test('trims surrounding whitespace and underscores', () {
      expect(humanizeDiseaseLabel('  _tomato_blight_ '), 'Tomato Blight');
    });

    test('preserves digits inside tokens', () {
      expect(humanizeDiseaseLabel('crop_v2_label'), 'Crop V2 Label');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run from project root:
```
flutter test test/utils/label_formatter_test.dart
```
Expected: compilation error or failures along the lines of `Error: Couldn't find constructor 'humanizeDiseaseLabel'` / `Target of URI doesn't exist`.

- [ ] **Step 3: Write the helper**

Create `lib/core/utils/label_formatter.dart`:

```dart
/// Converts a raw model label into a human-readable Title Case string.
///
/// Examples:
///   'tomato_bacterial_spot' -> 'Tomato Bacterial Spot'
///   'healthy'               -> 'Healthy'
///   'Tomato Bacterial Spot' -> 'Tomato Bacterial Spot' (idempotent)
///   ''                      -> ''
///
/// Splits on underscores and whitespace, collapses repeated separators,
/// title-cases each token (first char upper, rest lower).
String humanizeDiseaseLabel(String raw) {
  if (raw.isEmpty) return raw;
  final tokens = raw
      .split(RegExp(r'[_\s]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return '';
  return tokens
      .map((t) => t[0].toUpperCase() + t.substring(1).toLowerCase())
      .join(' ');
}
```

- [ ] **Step 4: Run the test to verify it passes**

```
flutter test test/utils/label_formatter_test.dart
```
Expected: `All tests passed!`.

- [ ] **Step 5: Stage for review (DO NOT commit)**

```
git add lib/core/utils/label_formatter.dart test/utils/label_formatter_test.dart
```
Then stop. Do not run `git commit`. Report "Task 1 staged — ready for review."

---

## Task 2: Apply humanizer in Disease Library screen

**Files:**
- Modify: `lib/features/library/library_screen.dart` (line 374, line 171 search)

- [ ] **Step 1: Add the import**

At the top of `lib/features/library/library_screen.dart`, after line 6 (`import '../../../data/models/disease_knowledge_model.dart';`), insert:

```dart
import '../../../core/utils/label_formatter.dart';
```

- [ ] **Step 2: Update the disease card title**

In `lib/features/library/library_screen.dart`, around line 374 the current code is:

```dart
              child: Text(kb.diseaseName,
```

Replace with:

```dart
              child: Text(humanizeDiseaseLabel(kb.diseaseName),
```

- [ ] **Step 3: Update the search filter to also match humanized form**

In `_applyFilter()` around line 167-176, the current code is:

```dart
  void _applyFilter() {
    _filtered = _all.where((kb) {
      final matchType = _filterType == null || kb.cropType == _filterType;
      final matchSearch = _search.isEmpty ||
          kb.diseaseName.toLowerCase().contains(_search.toLowerCase()) ||
          (kb.description?.toLowerCase().contains(_search.toLowerCase()) ??
              false);
      return matchType && matchSearch;
    }).toList();
  }
```

Replace the `matchSearch` line so users searching "Tomato Bacterial" find the humanized name:

```dart
  void _applyFilter() {
    _filtered = _all.where((kb) {
      final matchType = _filterType == null || kb.cropType == _filterType;
      final query = _search.toLowerCase();
      final humanized = humanizeDiseaseLabel(kb.diseaseName).toLowerCase();
      final matchSearch = _search.isEmpty ||
          kb.diseaseName.toLowerCase().contains(query) ||
          humanized.contains(query) ||
          (kb.description?.toLowerCase().contains(query) ?? false);
      return matchType && matchSearch;
    }).toList();
  }
```

- [ ] **Step 4: Run static analysis**

```
flutter analyze lib/features/library/library_screen.dart
```
Expected: no errors. Warnings about pre-existing code are OK.

- [ ] **Step 5: Stage for review (DO NOT commit)**

```
git add lib/features/library/library_screen.dart
```
Stop. Report "Task 2 staged — ready for review."

---

## Task 3: Apply humanizer in Scan Result screen and consolidate `_titleCaseLabel`

**Files:**
- Modify: `lib/features/scan/scan_result_screen.dart` (line 421, line 765, line 793-804)

The screen already has a private `_titleCaseLabel` helper (lines 793-804). Replace its usages with the new shared helper so we have one canonical implementation.

- [ ] **Step 1: Add the import**

At the top of `lib/features/scan/scan_result_screen.dart`, after the existing relative imports (after line 16 `import '../../../services/local_classifier_service.dart';`), insert:

```dart
import '../../../core/utils/label_formatter.dart';
```

- [ ] **Step 2: Update the result card title**

Around line 421, replace:

```dart
        Text(kb.diseaseName,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark)),
```

with:

```dart
        Text(humanizeDiseaseLabel(kb.diseaseName),
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark)),
```

- [ ] **Step 3: Update `_buildFallbackKnowledge` to use the shared helper**

Around line 765, the current line is:

```dart
    final title = _titleCaseLabel(label);
```

Replace with:

```dart
    final title = humanizeDiseaseLabel(label);
```

- [ ] **Step 4: Remove the now-dead private `_titleCaseLabel` helper**

Around lines 793-804, delete the entire method:

```dart
  String _titleCaseLabel(String value) {
    final normalized = _normalizeLabel(value);
    if (normalized.isEmpty) {
      return 'Unknown disease';
    }
    return normalized
        .split(' ')
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
```

Note: `_titleCaseLabel` had a fallback "Unknown disease" string when input was empty. The new helper returns `''` for empty input. To preserve behavior, change Step 3 to:

```dart
    final humanized = humanizeDiseaseLabel(label);
    final title = humanized.isEmpty ? 'Unknown disease' : humanized;
```

(Replace Step 3's edit with this version.)

- [ ] **Step 5: Run static analysis**

```
flutter analyze lib/features/scan/scan_result_screen.dart
```
Expected: no errors. If it complains about an unused `_normalizeLabel`, leave it — it's still used by `_resolveDiseaseMatch` at line 672.

- [ ] **Step 6: Stage for review (DO NOT commit)**

```
git add lib/features/scan/scan_result_screen.dart
```
Stop. Report "Task 3 staged — ready for review."

---

## Task 4: Apply humanizer in Diagnostic History screen

**Files:**
- Modify: `lib/features/scan/diagnostic_history_screen.dart` (line 162)

- [ ] **Step 1: Add the import**

At the top of `lib/features/scan/diagnostic_history_screen.dart`, after line 8 (`import '../auth/providers/auth_provider.dart';`), insert:

```dart
import '../../../core/utils/label_formatter.dart';
```

- [ ] **Step 2: Update the disease name in the history row**

Around line 162, replace:

```dart
                                child: Text(d.diseaseName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: AppColors.textDark)),
```

with:

```dart
                                child: Text(humanizeDiseaseLabel(d.diseaseName),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: AppColors.textDark)),
```

- [ ] **Step 3: Run static analysis**

```
flutter analyze lib/features/scan/diagnostic_history_screen.dart
```
Expected: no errors.

- [ ] **Step 4: Stage for review (DO NOT commit)**

```
git add lib/features/scan/diagnostic_history_screen.dart
```
Stop. Report "Task 4 staged — ready for review."

---

## Task 5: Apply humanizer in remaining display surfaces

**Files:**
- Modify: `lib/features/home/dashboard/dashboard_screen.dart` (line 616)
- Modify: `lib/features/crops/screens/crop_detail_screen.dart` (lines 684, 1192, 1283)
- Modify: `lib/features/chat/screens/chat_screen.dart` (lines 158, 568, 985)

These are the rest of the user-facing render sites for `diseaseName` / `detectedDiseaseName` found via `grep -n diseaseName`.

- [ ] **Step 1: Update dashboard_screen.dart**

Add import after the existing imports (find any `import '../../../core/...` line and add this just below it):

```dart
import '../../../core/utils/label_formatter.dart';
```

Around line 616, replace:

```dart
          name: items[i].diseaseName,
```

with:

```dart
          name: humanizeDiseaseLabel(items[i].diseaseName),
```

- [ ] **Step 2: Update crop_detail_screen.dart**

Add import after the existing `core/` imports near the top of the file:

```dart
import '../../../core/utils/label_formatter.dart';
```

Around line 684, replace:

```dart
            child: Text(diagnosis.diseaseName,
```

with:

```dart
            child: Text(humanizeDiseaseLabel(diagnosis.diseaseName),
```

Around line 1192, replace:

```dart
                    update.detectedDiseaseName!,
```

with:

```dart
                    humanizeDiseaseLabel(update.detectedDiseaseName!),
```

Around line 1283, replace:

```dart
                            child: Text(d.diseaseName,
```

with:

```dart
                            child: Text(humanizeDiseaseLabel(d.diseaseName),
```

- [ ] **Step 3: Update chat_screen.dart**

Add import after the existing `core/` imports near the top of the file:

```dart
import '../../../core/utils/label_formatter.dart';
```

Around line 158, replace:

```dart
              'Detected: ${diagnosis.diseaseName}',
```

with:

```dart
              'Detected: ${humanizeDiseaseLabel(diagnosis.diseaseName)}',
```

Around line 568, replace:

```dart
            diagnosis.diseaseName,
```

with:

```dart
            humanizeDiseaseLabel(diagnosis.diseaseName),
```

Around line 985, replace:

```dart
              Text('Detected: $diseaseName',
```

with:

```dart
              Text('Detected: ${humanizeDiseaseLabel(diseaseName)}',
```

**Important:** Do NOT change lines that pass `diseaseName` into models, providers, or AI prompts (the `diseaseName:` named-parameter sites and the `'disease_name':` map keys). Only display sites — anywhere a value is composed into a `Text`, `String` interpolation for UI, or a `name:` field on a UI item.

- [ ] **Step 4: Run static analysis on the three files**

```
flutter analyze lib/features/home/dashboard/dashboard_screen.dart lib/features/crops/screens/crop_detail_screen.dart lib/features/chat/screens/chat_screen.dart
```
Expected: no new errors introduced by these edits.

- [ ] **Step 5: Stage for review (DO NOT commit)**

```
git add lib/features/home/dashboard/dashboard_screen.dart lib/features/crops/screens/crop_detail_screen.dart lib/features/chat/screens/chat_screen.dart
```
Stop. Report "Task 5 staged — ready for review."

---

## Task 6: Add `flutter_local_notifications` and `timezone` packages

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add dependencies**

In `pubspec.yaml`, find the `# Voice` section (around line 54-56). Insert a new section right above `# Permissions`:

```yaml
  # Local Notifications
  flutter_local_notifications: ^17.2.3
  timezone: ^0.9.4
```

So the relevant block reads:

```yaml
  # Voice
  speech_to_text: ^7.0.0
  record: ^5.2.1

  # Local Notifications
  flutter_local_notifications: ^17.2.3
  timezone: ^0.9.4

  # Permissions
  permission_handler: ^11.3.1
```

- [ ] **Step 2: Run `flutter pub get`**

```
flutter pub get
```
Expected: resolves without errors. `pubspec.lock` will update.

If pub resolution fails on `record_linux` or other federated plugins, the existing `dependency_overrides` block in `pubspec.yaml` should still hold. If a new conflict appears (unlikely but possible), report it and stop — do NOT silently downgrade other packages.

- [ ] **Step 3: Stage for review (DO NOT commit)**

```
git add pubspec.yaml pubspec.lock
```
Stop. Report "Task 6 staged — ready for review. Pub get succeeded."

---

## Task 7: Update Android manifest with notification permissions and receivers

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Read the current manifest**

Read `android/app/src/main/AndroidManifest.xml` to see existing permissions and the `<application>` tag layout. The exact structure varies — confirm where `<uses-permission>` lines currently sit (above `<application>`) and what receivers already exist.

- [ ] **Step 2: Add the six required permissions**

Inside the `<manifest>` element, above the `<application>` opening tag, append these lines (skip any that are already present — check first):

```xml
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
```

- [ ] **Step 3: Add the two `flutter_local_notifications` receivers**

Inside the `<application>` element (anywhere among its children, conventionally after the main `<activity>`), add:

```xml
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
```

- [ ] **Step 4: Verify the manifest still parses**

```
flutter pub run flutter_lints:format
```
(If that command isn't available, just visually verify the file: matched tags, no malformed XML.)

- [ ] **Step 5: Stage for review (DO NOT commit)**

```
git add android/app/src/main/AndroidManifest.xml
```
Stop. Report "Task 7 staged — ready for review."

---

## Task 8: Define the `LocalNotificationsAdapter` interface and `reminderIdFor`

**Files:**
- Create: `lib/services/local_notifications_adapter.dart`
- Test: `test/services/reminder_id_for_test.dart`

- [ ] **Step 1: Write the failing tests for `reminderIdFor`**

Create `test/services/reminder_id_for_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cropcare_ai/services/local_notifications_adapter.dart';

void main() {
  group('reminderIdFor', () {
    test('returns deterministic ids for the same input', () {
      final a = reminderIdFor('task-123', '30min');
      final b = reminderIdFor('task-123', '30min');
      expect(a, b);
    });

    test('returns different ids for different reminder types', () {
      final id30 = reminderIdFor('task-123', '30min');
      final idDue = reminderIdFor('task-123', 'due');
      final idOver = reminderIdFor('task-123', 'overdue');
      expect({id30, idDue, idOver}.length, 3);
    });

    test('returns different ids for different task ids', () {
      final a = reminderIdFor('task-aaa', 'due');
      final b = reminderIdFor('task-bbb', 'due');
      expect(a, isNot(b));
    });

    test('always returns a non-negative 32-bit signed int', () {
      final ids = [
        reminderIdFor('a', '30min'),
        reminderIdFor('a', 'due'),
        reminderIdFor('a', 'overdue'),
        reminderIdFor('long-task-id-with-uuid-shape-9b8c7d6e', 'due'),
      ];
      for (final id in ids) {
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThanOrEqualTo(0x7FFFFFFF));
      }
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```
flutter test test/services/reminder_id_for_test.dart
```
Expected: import-not-found errors.

- [ ] **Step 3: Create the adapter interface, factory, and `reminderIdFor`**

Create `lib/services/local_notifications_adapter.dart`:

```dart
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
  final base = taskId.hashCode & 0x3FFFFFFF; // 30 bits, always positive
  final suffix = switch (kind) {
    '30min' => 0,
    'due' => 1,
    'overdue' => 2,
    _ => 3,
  };
  return (base << 2) | suffix;
}
```

- [ ] **Step 4: Create stub implementations so the import resolves**

The `impl.create()` factory needs both files to exist before the conditional import compiles. Create them as minimal stubs that we'll fill in next.

Create `lib/services/local_notifications_adapter_io.dart`:

```dart
import 'dart:async';
import 'local_notifications_adapter.dart';

LocalNotificationsAdapter create() => _IoLocalNotificationsAdapter();

class _IoLocalNotificationsAdapter implements LocalNotificationsAdapter {
  // Filled in by Task 9.
  final _tap = StreamController<String>.broadcast();

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required ReminderKind kind,
    String? payload,
  }) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Stream<String> get tapStream => _tap.stream;
}
```

Create `lib/services/local_notifications_adapter_web.dart`:

```dart
import 'dart:async';
import 'local_notifications_adapter.dart';

LocalNotificationsAdapter create() => _WebLocalNotificationsAdapter();

class _WebLocalNotificationsAdapter implements LocalNotificationsAdapter {
  // Filled in by Task 10.
  final _tap = StreamController<String>.broadcast();

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required ReminderKind kind,
    String? payload,
  }) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Stream<String> get tapStream => _tap.stream;
}
```

- [ ] **Step 5: Run the test to verify it passes**

```
flutter test test/services/reminder_id_for_test.dart
```
Expected: `All tests passed!`.

- [ ] **Step 6: Stage for review (DO NOT commit)**

```
git add lib/services/local_notifications_adapter.dart lib/services/local_notifications_adapter_io.dart lib/services/local_notifications_adapter_web.dart test/services/reminder_id_for_test.dart
```
Stop. Report "Task 8 staged — ready for review."

---

## Task 9: Implement the Android (`_io`) adapter

**Files:**
- Modify: `lib/services/local_notifications_adapter_io.dart`

- [ ] **Step 1: Replace the stub with the real Android implementation**

Replace the entire file with:

```dart
import 'dart:async';
import 'dart:io' show Platform;

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
    } catch (_) {
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
    } on PlatformException {
      // SCHEDULE_EXACT_ALARM not granted on Android 12+ — fall back to inexact.
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
```

- [ ] **Step 2: Run static analysis**

```
flutter analyze lib/services/local_notifications_adapter_io.dart
```
Expected: no errors. If `flutter_local_notifications` complains about a different `AndroidScheduleMode` enum value name in the version that resolved, adjust the enum name to match (likely `AndroidScheduleMode.exactAllowWhileIdle` — confirm via `flutter pub deps`).

- [ ] **Step 3: Run the still-passing reminderIdFor test**

```
flutter test test/services/reminder_id_for_test.dart
```
Expected: still passes. (We didn't touch the abstraction.)

- [ ] **Step 4: Stage for review (DO NOT commit)**

```
git add lib/services/local_notifications_adapter_io.dart
```
Stop. Report "Task 9 staged — ready for review."

---

## Task 10: Implement the Web (`_web`) adapter delegating to existing JS bridge

**Files:**
- Modify: `lib/services/local_notifications_adapter_web.dart`

- [ ] **Step 1: Replace the stub**

Replace the entire file with:

```dart
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
```

- [ ] **Step 2: Run static analysis**

```
flutter analyze lib/services/local_notifications_adapter_web.dart
```
Expected: no errors.

- [ ] **Step 3: Stage for review (DO NOT commit)**

```
git add lib/services/local_notifications_adapter_web.dart
```
Stop. Report "Task 10 staged — ready for review."

---

## Task 11: Refactor `NotificationService` to route through the adapter

**Files:**
- Modify: `lib/services/notification_service.dart`

- [ ] **Step 1: Replace the file with the orchestrator implementation**

Replace the entire contents of `lib/services/notification_service.dart` with:

```dart
import 'dart:async';

import '../data/models/treatment_task_model.dart';
import 'local_notifications_adapter.dart';

/// Schedules treatment-task reminders via the platform-specific
/// [LocalNotificationsAdapter]. Three reminder points per task:
///
///   1. [ReminderKind.thirtyMin]  — `dueAt - 30min`
///   2. [ReminderKind.due]        — at `dueAt`
///   3. [ReminderKind.overdue]    — `dueAt + 4h` (skipped if task completed)
///
/// Past-due reminders are silently skipped by the adapter.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;
  NotificationService._();

  final LocalNotificationsAdapter _adapter = createLocalNotificationsAdapter();

  Stream<String> get tapStream => _adapter.tapStream;

  // ─── Permission ───────────────────────────────────────────────────────────

  Future<bool> requestPermission() => _adapter.requestPermission();

  // ─── Scheduling ───────────────────────────────────────────────────────────

  /// Cancel everything currently scheduled and replace with reminders for
  /// the given [tasks]. Idempotent — safe to call repeatedly.
  Future<void> scheduleForTasks(List<TreatmentTaskModel> tasks) async {
    await _adapter.init();
    await _adapter.cancelAll();
    for (final task in tasks) {
      await _scheduleSingle(task);
    }
  }

  Future<void> _scheduleSingle(TreatmentTaskModel task) async {
    final dueAt = task.dueAt;
    final title = task.title;
    final payload = 'task:${task.id}';

    await _adapter.schedule(
      id: reminderIdFor(task.id, ReminderKind.thirtyMin.token),
      when: dueAt.subtract(const Duration(minutes: 30)),
      title: 'Upcoming Task — 30 min',
      body: '"$title" is due in 30 minutes. Get ready!',
      kind: ReminderKind.thirtyMin,
      payload: payload,
    );

    await _adapter.schedule(
      id: reminderIdFor(task.id, ReminderKind.due.token),
      when: dueAt,
      title: 'Task Due Now',
      body: '"$title" is due. Complete it and log your progress.',
      kind: ReminderKind.due,
      payload: payload,
    );

    await _adapter.schedule(
      id: reminderIdFor(task.id, ReminderKind.overdue.token),
      when: dueAt.add(const Duration(hours: 4)),
      title: 'Task Overdue',
      body: '"$title" is overdue. Mark it done or reschedule.',
      kind: ReminderKind.overdue,
      payload: payload,
    );
  }

  // ─── Cancel ───────────────────────────────────────────────────────────────

  Future<void> cancelAll() => _adapter.cancelAll();

  Future<void> cancelForTask(String taskId) async {
    await _adapter.cancel(reminderIdFor(taskId, ReminderKind.thirtyMin.token));
    await _adapter.cancel(reminderIdFor(taskId, ReminderKind.due.token));
    await _adapter.cancel(reminderIdFor(taskId, ReminderKind.overdue.token));
  }
}
```

- [ ] **Step 2: Update the existing call sites that used the old sync API**

The existing callers in `lib/features/notifications/providers/notifications_provider.dart` call:

- `NotificationService.instance.requestPermission();` (sync) at line 47 → now returns `Future<bool>`. The call is fire-and-forget (return value ignored), so add `unawaited(...)`:

  Change line 47 from:
  ```dart
      NotificationService.instance.requestPermission();
  ```
  to:
  ```dart
      // ignore: discarded_futures
      NotificationService.instance.requestPermission();
  ```

- `NotificationService.instance.scheduleForTasks(_todayTasks);` at lines 48 and 148 → now returns `Future<void>`. Same fire-and-forget treatment:

  Change line 48 from:
  ```dart
      NotificationService.instance.scheduleForTasks(_todayTasks);
  ```
  to:
  ```dart
      // ignore: discarded_futures
      NotificationService.instance.scheduleForTasks(_todayTasks);
  ```

  Change line 148 from:
  ```dart
      NotificationService.instance.scheduleForTasks(_todayTasks);
  ```
  to:
  ```dart
      // ignore: discarded_futures
      NotificationService.instance.scheduleForTasks(_todayTasks);
  ```

- [ ] **Step 3: Verify the JS bridge is now used only via the web adapter**

The two existing files `_notification_js_stub.dart` and `_notification_js_web.dart` are still needed — `local_notifications_adapter_web.dart` from Task 10 imports them. Do NOT delete them.

Confirm no other file in `lib/` imports them directly anymore (the rewritten `notification_service.dart` from Step 1 should no longer reference them):

```
grep -rn "_notification_js_" lib/
```
Expected output: only `lib/services/local_notifications_adapter_web.dart` references them. If anything else does, report it and stop — do not silently fix.

- [ ] **Step 4: Run static analysis**

```
flutter analyze lib/services/notification_service.dart lib/features/notifications/providers/notifications_provider.dart
```
Expected: no errors.

- [ ] **Step 5: Run all unit tests**

```
flutter test
```
Expected: all tests pass (label_formatter, reminderIdFor, plus any pre-existing tests).

- [ ] **Step 6: Stage for review (DO NOT commit)**

```
git add lib/services/notification_service.dart lib/features/notifications/providers/notifications_provider.dart
```
Stop. Report "Task 11 staged — ready for review. All unit tests pass."

---

## Task 12: Manual on-device smoke test for notifications

**Files:** _no code changes — purely verification_

This task validates the Android notification path on a real device. It is a **gate**, not optional — the code can compile without notifications working.

- [ ] **Step 1: Build and install a debug APK on an Android device (API 30+)**

```
flutter run -d <android-device-id>
```
or
```
flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 2: Register a fresh test account and create a crop**

In the app: register → onboarding → create one crop (any type).

- [ ] **Step 3: Add a treatment task due 31 minutes from now**

Use the existing add-task UI (or the disease-detection flow that auto-creates tasks). Confirm via the Notifications screen → Tasks tab that the task appears with the expected `dueAt`.

- [ ] **Step 4: Verify reminder firing**

| t-relative-to-due | Expected | Pass criteria |
|---|---|---|
| due - 30min ± 60s | 30-min warning notification fires | Visible in tray, channel = `task_30min`, title = "Upcoming Task — 30 min" |
| due ± 60s | At-due notification fires | Visible in tray, title = "Task Due Now" |
| due + 4h ± 60s | Overdue notification fires (only if task still pending) | Visible in tray, title = "Task Overdue" |

For the impatient version: change device clock forward (Settings → Date & time → Set time) to `due - 30min - 30s` and wait 60 seconds. Repeat for `due` and `due + 4h`.

- [ ] **Step 5: Verify cancel-on-complete**

Set device clock back to `due - 30min - 90s`. Mark the task as Done in the Notifications → Tasks screen. Wait until past `due + 4h`. Expected: no overdue notification fires (the rescheduling in `NotificationsProvider.markTaskDone` cancels the remaining reminders).

- [ ] **Step 6: Verify boot-survival**

Reschedule a task for ~10 minutes from now. Power-cycle the device. Expected: when the device boots back up, the notification still fires within 60s of the scheduled time. (Validates the `BOOT_COMPLETED` receiver from Task 7.)

- [ ] **Step 7: Document the result**

Create `docs/superpowers/testing/2026-05-08-phase1-notifications-smoke.md` with one of:
- "All steps passed on `<device model> Android <version>`."
- A specific failure description with logcat excerpt (`adb logcat -s flutter,FlutterLocalNotificat:V`).

If failure, do NOT proceed to Task 13. Report and stop.

- [ ] **Step 8: Stage the testing report (DO NOT commit)**

```
git add docs/superpowers/testing/2026-05-08-phase1-notifications-smoke.md
```
Stop. Report "Task 12 complete. Smoke test result: <pass|fail>."

---

## Task 13: Manual offline photo diagnosis verification on Android

**Files:** _no code changes unless a regression is found — verification + targeted fixes only_

- [ ] **Step 1: Baseline (online) scan**

With the device online and signed in to the test account: scan a photo of a tomato leaf (use the curated test images in `assets/images/` if available, or any tomato leaf photo). Confirm a normal diagnosis flows through `scan_result_screen.dart` and a result card renders.

- [ ] **Step 2: Toggle airplane mode on**

Settings → Airplane mode → ON. Confirm the device shows no network.

- [ ] **Step 3: Run the offline scan**

In the app: Scan tab → Take Photo → use the same/similar tomato leaf photo. Verify, in order:

1. Camera capture works (no errors).
2. The result screen does not show "AI backend unavailable" — it should fall through to the local TFLite path inside `_analyze()` ([lib/features/scan/scan_result_screen.dart:74-86](../../../lib/features/scan/scan_result_screen.dart#L74-L86)).
3. A diagnosis result card renders with a humanized disease name (Task 3) and treatment steps from the local KB.
4. Tap "Yes, track it" — confirm a `DiagnosisModel` is written to local SQLite. Verify by inspecting `cropcare_ai.db` via `adb shell run-as <package> sqlite3` if needed, or by going back online and seeing the diagnosis appear in `Diagnostic History`.

- [ ] **Step 4: Toggle airplane mode off, verify sync**

Restore network. Within ~30 seconds (or after a manual refresh on the History screen), the diagnosis written offline should sync to Supabase via the existing `sync_service`.

- [ ] **Step 5: Document the result**

Create `docs/superpowers/testing/2026-05-08-phase1-offline-scan-smoke.md` with:
- "All steps passed on `<device>`. Local TFLite returned `<label>` with `<confidence>` confidence; KB lookup matched `<disease name>`." OR
- A specific failure description.

- [ ] **Step 6: If failure, address common known issues**

Likely failure modes (only fix the one(s) you observe — do not pre-emptively code):

1. **TFLite model not found in release/debug.** Check `assets/models/cropcare_efficientnet_v2.tflite` is listed under `flutter.assets` in `pubspec.yaml`. It is, per existing config — but verify it's actually packaged:
   ```
   unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep tflite
   ```

2. **Local classifier throws because remote backend was the only path tried.** Inspect [lib/features/scan/scan_result_screen.dart:73-86](../../../lib/features/scan/scan_result_screen.dart#L73-L86): the local classifier is tried first inside a `try`, and falls through to remote on any exception. If the local path is throwing silently and falling through to the remote (which then fails because offline), surface the error: temporarily wrap the `localClassifier.classifyImage` call in a try-catch that logs the exception, run the scan once, capture the log, and then revert the logging.

3. **Disease KB not seeded on a fresh install.** The `disease_knowledge_base` table may be empty. Check by going to Library tab while offline — if it shows "no results," the KB needs seeding via the Library import flow (run that step online, then go offline). The offline scan needs a populated KB to render the result card with treatment steps.

For each issue found, write the targeted fix as a separate small commit-ready change. Do NOT commit. Stage and report.

- [ ] **Step 7: Stage the testing report and any fixes (DO NOT commit)**

```
git add docs/superpowers/testing/2026-05-08-phase1-offline-scan-smoke.md
# plus any changed files from Step 6
```
Stop. Report "Task 13 complete. Offline scan result: <pass|fail with details>."

---

## Definition of Done for Phase 1

After all 13 tasks have been staged and reviewed:

- [ ] `humanizeDiseaseLabel` exists with passing unit tests.
- [ ] All eight display-site files (`library`, `scan_result`, `diagnostic_history`, `dashboard`, `crop_detail`, `chat`) render humanized disease names.
- [ ] `flutter_local_notifications` and `timezone` are in `pubspec.yaml` and `pubspec.lock`.
- [ ] `LocalNotificationsAdapter` interface + Android (`_io`) + Web (`_web`) implementations exist.
- [ ] `NotificationService` orchestrates through the adapter; old `Timer`-and-JS-only path is gone (web path still uses JS bridge through the new web adapter).
- [ ] `AndroidManifest.xml` has the six permissions and two receivers.
- [ ] `flutter test` passes.
- [ ] `flutter analyze` shows no new errors.
- [ ] On-device notification smoke test passed (Task 12 documented).
- [ ] On-device offline-scan smoke test passed (Task 13 documented).
- [ ] All changes are staged but not committed — repo owner reviews and commits manually.
