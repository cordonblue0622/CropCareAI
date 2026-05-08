# Phase 4 — Offline Voice & Dashboard UI Polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the voice assistant route through on-device `speech_to_text` when offline, and fix dashboard layout bugs found during a passive review pass.

**Architecture:** Single connectivity branch added to `_startVoiceCapture` before recording starts; `_startSpeechFallback` gains an `onDevice` parameter forwarded to `SpeechListenOptions`. Dashboard changes are localized fixes (overflow, ellipsis, padding) within `dashboard_screen.dart` and its private sub-widgets.

**Tech Stack:** Flutter, Provider, `speech_to_text: ^7.0.0`, existing `ConnectivityService`. No new packages.

**Spec:** `docs/superpowers/specs/2026-05-08-phase4-offline-voice-and-dashboard-design.md`

**Branch / commit policy:** User commits manually (memory: never auto-commit). Each task ends with a staged-only message; user reviews and runs `git commit` themselves.

---

## File Structure

| File | Role |
|------|------|
| `lib/features/voice/voice_screen.dart` | Add `_startSpeechFallback({onDevice})`; add connectivity branch in `_startVoiceCapture`; refresh status messages |
| `test/features/voice/voice_offline_routing_test.dart` (new) | Widget test: offline → fallback path is taken; online → not taken |
| `lib/features/home/dashboard/dashboard_screen.dart` | Targeted layout fixes for issues found during review |

No new packages. No schema changes.

---

## Task 1: Extend `_startSpeechFallback` to accept `onDevice`

**Files:**
- Modify: `lib/features/voice/voice_screen.dart`

**Context:** `_startSpeechFallback` currently always calls `_speech.listen` with `SpeechListenOptions(partialResults: true, autoPunctuation: true, listenMode: ListenMode.dictation)`. We need to optionally pass `onDevice: true` for the offline path. Existing callers (permission denied, recorder failure) must keep working — default the new param to `false`.

- [ ] **Step 1: Edit the method signature and listen options**

In `lib/features/voice/voice_screen.dart`, change `_startSpeechFallback`:

```dart
Future<void> _startSpeechFallback(
  String message, {
  bool onDevice = false,
}) async {
  if (!_available) {
    if (!mounted) return;
    setState(() {
      _listening = false;
      _usingSpeechFallback = false;
      _errorText = 'Microphone is unavailable on this device.';
    });
    return;
  }

  if (!mounted) return;
  setState(() {
    _listening = true;
    _usingSpeechFallback = true;
    _commandHandled = false; // reset for new session
    _errorText = message;
    _words = '';
  });

  await _speech.listen(
    onResult: (result) {
      final transcript = result.recognizedWords.trim();
      if (mounted) {
        setState(() => _words = transcript);
      }
      if (_usingSpeechFallback &&
          result.finalResult &&
          transcript.isNotEmpty &&
          !_commandHandled) {
        _commandHandled = true;
        if (mounted) {
          setState(() => _listening = false);
        }
        _handleCommand(transcript);
      }
    },
    listenFor: const Duration(minutes: 2),
    pauseFor: const Duration(seconds: 8),
    listenOptions: SpeechListenOptions(
      partialResults: true,
      autoPunctuation: true,
      listenMode: ListenMode.dictation,
      onDevice: onDevice,
    ),
  );
}
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/features/voice/voice_screen.dart`
Expected: No new warnings or errors.

- [ ] **Step 3: Stage**

```bash
git add lib/features/voice/voice_screen.dart
```

Do NOT commit. Report staged changes to controller.

---

## Task 2: Add connectivity branch in `_startVoiceCapture`

**Files:**
- Modify: `lib/features/voice/voice_screen.dart`

**Context:** `_startVoiceCapture` currently asks the recorder for permission, then starts WAV recording. We add a connectivity check at the top: if offline, route to `_startSpeechFallback` with `onDevice: true` and return. `ConnectivityService` is registered in `app.dart` and exposes `Future<bool> get isConnected`. Treat any error from the check as "offline" (defensive — see spec §6).

- [ ] **Step 1: Add the import for ConnectivityService**

If not already imported, add at top of `lib/features/voice/voice_screen.dart`:

```dart
import '../../services/connectivity_service.dart';
```

(Check existing imports first; the file already imports from `../../../core/...` and `../../../data/...` — the connectivity import follows the same `../../../services/...` pattern. Use the path that matches the file's actual depth: voice_screen.dart is at `lib/features/voice/voice_screen.dart`, so use `../../services/connectivity_service.dart`.)

- [ ] **Step 2: Insert the connectivity check at the top of `_startVoiceCapture`**

Replace the body of `_startVoiceCapture`:

```dart
Future<void> _startVoiceCapture() async {
  setState(() {
    _errorText = null;
    _words = '';
  });

  // If offline, skip the backend Whisper round-trip and use on-device STT.
  bool isOnline;
  try {
    isOnline = await context.read<ConnectivityService>().isConnected;
  } catch (_) {
    isOnline = false;
  }
  if (!isOnline) {
    await _startSpeechFallback(
      'You are offline. Using on-device speech recognition.',
      onDevice: true,
    );
    return;
  }

  try {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      await _startSpeechFallback(
        'Microphone permission was denied. Using device speech recognition instead.',
      );
      return;
    }

    final recordingPath = await _buildRecordingPath();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 128000,
      ),
      path: recordingPath,
    );

    if (!mounted) return;
    setState(() {
      _listening = true;
      _usingSpeechFallback = false;
    });
  } catch (_) {
    await _startSpeechFallback(
      'Backend voice capture is unavailable on this device. Using device speech recognition instead.',
    );
  }
}
```

(Note: the `context.read` runs while the State is mounted — we just executed `setState` synchronously above without an `await`, so `context` is safe to read at that point. After the `await`, do NOT touch `context` again unless `mounted` is checked, which the existing code already does.)

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze lib/features/voice/voice_screen.dart`
Expected: No errors. A `use_build_context_synchronously` lint may appear if the `context.read` is flagged after a prior `await` — there is no await before this line in the new code, so the lint should not trigger. If it does, restructure to read `ConnectivityService` into a local before the first `setState`.

- [ ] **Step 4: Stage**

```bash
git add lib/features/voice/voice_screen.dart
```

---

## Task 3: Write the offline-routing widget test

**Files:**
- Create: `test/features/voice/voice_offline_routing_test.dart`

**Context:** Verify that when `ConnectivityService.isConnected` returns `false`, the `VoiceScreen` does not call `AiBackendService.transcribeAudio` and shows the offline message. We override providers so no real platform channels are touched. We do NOT assert speech_to_text actually starts listening — `_speech.initialize` returns false in the test environment, so the screen will show "Microphone is unavailable on this device." after the offline branch is taken. That is fine for the assertion: the offline branch was taken (we set `_errorText` to the offline message before checking `_available`... wait — re-check `_startSpeechFallback`: it checks `_available` FIRST and bails to "Microphone is unavailable" if not available, so the offline message will NOT appear in the test.

Adjust assertion strategy: instead of asserting the user-visible text, assert that `AiBackendService.transcribeAudio` is never called. We use a `FakeAiBackendService` whose `transcribeAudio` throws if invoked. Tap the mic in offline mode and pump — no exception means the backend path was avoided.

Also assert the inverse: with `isConnected = true`, the recorder path is attempted. Since `record` plugin requires platform channels, the recorder will fail; we cannot easily assert success. So we only run the offline assertion (it is the regression-relevant case).

- [ ] **Step 1: Write the failing test**

Create `test/features/voice/voice_offline_routing_test.dart`:

```dart
import 'dart:typed_data';

import 'package:cropcare_ai/data/remote/ai_backend_service.dart';
import 'package:cropcare_ai/features/voice/voice_screen.dart';
import 'package:cropcare_ai/services/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeConnectivityService extends ConnectivityService {
  _FakeConnectivityService(this._online);
  final bool _online;
  @override
  Future<bool> get isConnected async => _online;
}

class _FakeAiBackendService extends AiBackendService {
  bool transcribeCalled = false;

  @override
  Future<TranscriptionResponse> transcribeAudio({
    required Uint8List audioBytes,
    required String filename,
  }) async {
    transcribeCalled = true;
    throw StateError('transcribeAudio must not be called when offline');
  }
}

void main() {
  testWidgets(
    'offline mic tap does not invoke backend transcribeAudio',
    (tester) async {
      final fakeAi = _FakeAiBackendService();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ConnectivityService>.value(
              value: _FakeConnectivityService(false),
            ),
            Provider<AiBackendService>.value(value: fakeAi),
          ],
          child: const MaterialApp(home: VoiceScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Find the mic button — VoiceScreen's primary tap target. The exact
      // finder may need adjustment after reading the build method; if the
      // button is a GestureDetector wrapping a circular Icon, use byIcon.
      final micButton = find.byIcon(Icons.mic);
      // If the icon differs (e.g., mic_none, mic_rounded), adjust here.
      if (micButton.evaluate().isEmpty) {
        // Fall back: find any GestureDetector and tap the largest one.
        // For determinism we instead skip the test with a clear message.
        fail('Mic button icon not found — check VoiceScreen build for the actual icon');
      }
      await tester.tap(micButton.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakeAi.transcribeCalled, isFalse);
    },
  );
}
```

- [ ] **Step 2: Run the test to see what fails / what icon name we need**

Run: `flutter test test/features/voice/voice_offline_routing_test.dart`
Expected: PASS, OR a clear `fail()` from the icon-finder fallback indicating which icon name `VoiceScreen` actually uses. If the latter, read `voice_screen.dart` build method for the mic icon, update `find.byIcon(...)` to match, and re-run.

- [ ] **Step 3: Adjust finder if needed and re-run**

If Step 2 reported the wrong icon, update `find.byIcon(Icons.mic)` to the actual icon used (e.g., `Icons.mic_rounded`). Re-run:

Run: `flutter test test/features/voice/voice_offline_routing_test.dart`
Expected: PASS.

- [ ] **Step 4: Stage**

```bash
git add test/features/voice/voice_offline_routing_test.dart
```

---

## Task 4: Manual smoke on Pixel 7a (voice paths)

**Files:** none (manual)

**Context:** Phases 1–3 were validated on the user's Pixel 7a. Phase 4 voice changes need on-device verification because emulators rarely have a working speech recognizer.

- [ ] **Step 1: Build & install**

Run: `flutter run --release` (or `flutter install` if a previous build is fresh).

- [ ] **Step 2: Test offline path**

1. Put device in airplane mode.
2. Open Voice Assistant.
3. Tap mic, say "scan this crop".
4. Expected: status shows "You are offline. Using on-device speech recognition." then transcription appears, then ScanScreen opens.

- [ ] **Step 3: Test online path**

1. Disable airplane mode, confirm Wi-Fi connected.
2. Open Voice Assistant.
3. Tap mic, say "what disease is this".
4. Expected: status shows "Recording your voice command..." → "Transcribing with Whisper..." → ChatScreen opens with the query. Behavior identical to Phase 3.

- [ ] **Step 4: Test permission-denied path (regression)**

1. Settings → CropCare AI → Permissions → revoke microphone.
2. Reopen Voice Assistant, tap mic.
3. Expected: status shows "Microphone permission was denied. Using device speech recognition instead." and prompts the OS for permission via `speech_to_text`.
4. Re-grant mic permission for the rest of testing.

Report results to controller. If any path regresses, return BLOCKED with reproduction steps.

---

## Task 5: Dashboard passive review — identify issues

**Files:**
- Read-only: `lib/features/home/dashboard/dashboard_screen.dart` and any sub-widget files it imports

**Context:** Per spec §3.2, fix only concrete observed issues. This task PRODUCES A LIST of issues; Task 6 fixes them. The list lives in the controller's TodoWrite or in a comment on the next task — no file output needed.

- [ ] **Step 1: Read the dashboard file end-to-end**

Read: `lib/features/home/dashboard/dashboard_screen.dart` (full file, 1244 lines).
Note the private sub-widgets defined inside it (`_VitalityCard`, `_ActiveCropCard`, `_TodayTasksCard`, `_DashboardTaskRow`, `_SmartTipCard`, `_DiseaseCard`, `_SectionHeader`, `_SearchBar`, `_DashboardCropPlaceholder`, `_SparklinePainter`).

- [ ] **Step 2: Run the app on the Pixel 7a and exercise every section**

Run: `flutter run` → Dashboard.
With seeded data: scroll top to bottom, watch debug console for `RenderFlex overflowed`, `BoxConstraints forces an infinite`, or similar. Note row/column visual issues:
- Greeting row: long first names with "Update <task>" link — does the link ellipsize?
- Vitality cards (140w × 140h): does the trend label fit?
- Active crop cards: long crop names — `maxLines: 1` already set, confirm it triggers
- Today's Tasks card: missed + due-today both populated, lots of rows — check spacing
- Smart Tip card: long messages — does the text wrap cleanly inside the green container?
- Common Diseases cards (140w × 160h): long humanized labels — do they overflow or get clipped?
- Empty states: clear `_diseases` cache and confirm empty card layouts.

Repeat with no active crops and no tasks.
Repeat at split-screen / narrow width if Pixel 7a supports it.

- [ ] **Step 3: Produce a fix list**

Output a bullet list of concrete issues with line numbers, e.g.:
- `dashboard_screen.dart:382-389` — "Update <task>" Text inside `Flexible` ellipsizes correctly; no fix.
- `dashboard_screen.dart:1228-1237` — `_DiseaseCard` name + risk inside a 160px-tall column with `MainAxisAlignment.end` can clip when humanized label wraps to 2 lines on narrow screens. Fix: add `maxLines: 2, overflow: TextOverflow.ellipsis` to the name `Text`.
- `dashboard_screen.dart:864-873` — status badge text uses `crop.status.name.toUpperCase()`; "RECOVERING" + 8px padding can collide with image edge on narrow widths. Fix: clamp badge to `maxLines: 1`.
- (etc.)

If NO issues are found, the list is empty and Task 6 is a no-op (mark complete, move on). Pass the list to Task 6.

- [ ] **Step 4: Report findings to controller**

Output the list in the agent reply. No staged changes from this task.

---

## Task 6: Apply dashboard fixes

**Files:**
- Modify: `lib/features/home/dashboard/dashboard_screen.dart` (targeted edits only)

**Context:** Apply each fix from Task 5's list. ONE fix per `Edit` call, smallest possible change. Do not refactor surrounding code. Do not add new widgets. If Task 5 produced an empty list, mark this task done with "no issues found" and skip the steps below.

- [ ] **Step 1: For each issue in the Task 5 list, make the minimal edit**

Example template per fix:

```
// Before (line N):
Text(name, style: const TextStyle(...))

// After:
Text(
  name,
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
  style: const TextStyle(...),
)
```

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/features/home/dashboard/dashboard_screen.dart`
Expected: No new warnings.

- [ ] **Step 3: Re-run on device, re-exercise the same scenarios from Task 5 Step 2**

Confirm each previously-observed issue is gone and nothing new broke. Watch the debug console for overflow warnings — must be zero during a full top-to-bottom scroll.

- [ ] **Step 4: Stage**

```bash
git add lib/features/home/dashboard/dashboard_screen.dart
```

---

## Task 7: Final regression sweep

**Files:** none (manual)

**Context:** Make sure Phases 1–3 features still work after Phase 4 changes.

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: All existing tests pass plus the new `voice_offline_routing_test.dart`. Known FFI flakiness in `VideoCleanupService` tests (deferred to Phase 5) — if it appears, run `flutter clean` then re-run; report as the known limitation, not a Phase 4 regression.

- [ ] **Step 2: Smoke the four major features on device**

1. Calendar (Phase 2): open, tap a day, confirm tasks render.
2. Health graph (Phase 2): open a crop, confirm chart renders.
3. Notifications (Phase 1+2): trigger one, tap, confirm deep-link.
4. Video diagnosis (Phase 3): record a 15s video, confirm save + thumbnail + tombstone behavior.

- [ ] **Step 3: Report results**

If anything regresses, return BLOCKED with reproduction steps. If clean, controller hands off to user for final commit.

---

## Done Criteria

- All 7 tasks marked complete (TodoWrite).
- `flutter test` green (modulo the known Phase 5 FFI-isolation flake).
- All four manual rehearsals on Pixel 7a pass.
- User has staged changes ready to review and commit manually (NEVER auto-commit per memory rule).

## Phase 5 Backlog (post-defense)

- Chat-provider write-side video metadata
- Sync-service video upload to Supabase
- `VideoCleanupService` test isolation (per-test temp DB)
- Optional: voice language picker, continuous mode
