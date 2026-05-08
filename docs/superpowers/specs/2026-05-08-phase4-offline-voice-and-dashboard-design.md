# Phase 4 — Offline Voice & Dashboard UI Polish

**Date:** 2026-05-08
**Status:** Approved (scope confirmed by user)
**Predecessors:** Phases 1, 2, 3 (complete and tested on Pixel 7a)
**Successor:** Phase 5 (post-defense — chat-provider video metadata write-side, sync-service video upload, FFI test isolation)

---

## 1. Goal

Make the voice assistant usable offline, and clean up dashboard layout issues found during a passive review pass. No backend, schema, or new dependency changes.

## 2. Scope

**In scope:**
1. **Offline voice capture** — when the device is offline, route voice input through `speech_to_text` with `onDevice: true` instead of attempting a backend Whisper round-trip that will fail.
2. **Dashboard UI fixes** — passive review of `lib/features/home/dashboard/dashboard_screen.dart` and adjacent widgets. Fix layout bugs (overflow, alignment, spacing, contrast) found during review. No new sections, no behavior changes.

**Explicitly out of scope (deferred to Phase 5):**
- Chat-provider write-side video metadata
- Sync-service video upload
- FFI test isolation fixes for `VideoCleanupService` tests
- Any voice features beyond connectivity-aware routing (no language picker, no continuous mode, no command grammar changes)
- Any dashboard redesign or new widgets

## 3. Architecture

### 3.1 Offline Voice Flow

The existing `_VoiceScreenState` (`lib/features/voice/voice_screen.dart`) already has a dual-path design:

- **Primary path:** `_startVoiceCapture` records WAV via `AudioRecorder`, then `_stopRecordingAndTranscribe` uploads to backend Whisper via `AiBackendService.transcribeAudio`.
- **Fallback path:** `_startSpeechFallback` uses `speech_to_text` directly on the device.

Today, the fallback only triggers when the mic permission is denied or `_recorder.start` throws. If the device is offline the user records audio, the backend call fails with a generic error ("Voice transcription failed. Check the backend connection..."), and the user is left without a result.

Phase 4 adds a **proactive connectivity check** before recording starts. The check uses the existing `ConnectivityService` (`lib/services/connectivity_service.dart`) which is already provider-registered.

```
_toggleListen → _startVoiceCapture
                    │
                    ▼
              isConnected? ── no ──► _startSpeechFallback(offlineMessage, onDevice: true)
                    │ yes
                    ▼
              record WAV → backend Whisper (existing path, unchanged)
```

`_startSpeechFallback` is extended to pass `onDevice: true` on `SpeechListenOptions` so Android uses the local recognizer (no cloud round-trip from `speech_to_text` itself). When `onDevice` is requested but unsupported on the device, the call still falls back to the platform's default recognizer — we accept that as best-effort and surface the error if listening fails to start.

### 3.2 Dashboard UI Fixes

Passive review only. The implementer reads `dashboard_screen.dart` and the immediate sub-widgets it owns (`_VitalityCard`, `_ActiveCropCard`, `_TodayTasksCard`, `_DashboardTaskRow`, `_SmartTipCard`, `_DiseaseCard`, `_SectionHeader`, `_SearchBar`), runs the app on the connected Pixel 7a, and fixes any of these classes of issue found:

- Text overflow without `maxLines` + `TextOverflow.ellipsis`
- `Row` children that can overflow without `Expanded`/`Flexible`
- Inconsistent padding/spacing between similar cards
- Hardcoded heights that clip content (e.g., `SizedBox(height: 160)` truncating `_DiseaseCard` text on small screens)
- Missing `crossAxisAlignment` causing visual drift
- `Color.withOpacity` deprecation warnings (Flutter 3.27+) — replace with `.withValues(alpha:)` only if the codebase already uses that pattern; otherwise leave (avoid scope creep)

**Out of scope:** color palette changes, layout restructuring, new animations, semantic role changes.

## 4. Components Touched

| File | Change |
|------|--------|
| `lib/features/voice/voice_screen.dart` | Add connectivity check in `_startVoiceCapture`; pass `onDevice: true` in `_startSpeechFallback`; refresh status messages |
| `lib/features/home/dashboard/dashboard_screen.dart` | Fix overflow / alignment / spacing issues found during review |
| `test/features/voice/voice_offline_routing_test.dart` (new) | Verify offline-detected path takes the speech fallback |

No new files in `lib/`. No new packages.

## 5. Data Flow & State

No new state. The change is a single async branch in `_startVoiceCapture`:

```dart
final connectivity = context.read<ConnectivityService>();
final isOnline = await connectivity.isConnected;
if (!isOnline) {
  await _startSpeechFallback(
    'You are offline. Using on-device speech recognition.',
    onDevice: true,
  );
  return;
}
// existing recording flow
```

`_startSpeechFallback` gains an `onDevice` parameter (default `false`) that is passed to `SpeechListenOptions(onDevice: onDevice, ...)`. Existing callers (permission-denied, recorder-failure) continue to pass nothing and behave as before.

## 6. Error Handling

- **`speech_to_text` not initialized / unavailable:** existing branch already shows "Microphone is unavailable on this device." — unchanged.
- **`onDevice: true` unsupported by platform:** `speech_to_text` falls back to the default recognizer on its own. We don't try to detect this — if listening fails to produce results, the existing "No speech was detected." message handles it.
- **Connectivity check throws:** treat as offline (defensive — better UX to use the local recognizer than to dead-end the user).

## 7. Testing

### 7.1 Unit / widget test (new)

`test/features/voice/voice_offline_routing_test.dart` — pumps `VoiceScreen` with a fake `ConnectivityService` whose `isConnected` future resolves to `false`. Triggers the mic tap. Asserts the screen shows the offline status message ("You are offline. Using on-device speech recognition.") and does NOT call `AiBackendService.transcribeAudio`.

A second test variant uses `isConnected = true` and asserts the offline message is absent. We do not assert the recorder actually starts (that requires platform channels) — only that the offline branch is not taken.

The test uses Provider overrides for `ConnectivityService` and `AiBackendService` (the latter mocked to throw if called). It does not require sqflite or platform channels.

### 7.2 Manual rehearsal

On the Pixel 7a:
1. Airplane mode ON → Voice screen → tap mic → speak "scan this crop" → expect on-device transcription and navigation to ScanScreen.
2. Airplane mode OFF → Voice screen → tap mic → speak → expect Whisper transcription as before.
3. Open Dashboard, scroll through every section, rotate device, check at narrow width (split-screen) — confirm fixed issues stay fixed and nothing new broke.

## 8. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `onDevice: true` silently degrades to cloud on some Android builds | Acceptable; user sees a result either way. Documented in spec. |
| Connectivity check delays mic startup noticeably | `ConnectivityService.isConnected` is a single `Connectivity().checkConnectivity()` call (~tens of ms). No spinner needed. |
| Dashboard fixes scope-creep into a redesign | Plan limits each fix to one concrete observed issue with a before/after note. Reviewer rejects layout restructuring. |

## 9. Acceptance Criteria

- [ ] Voice screen routes to `speech_to_text` (`onDevice: true`) when offline; backend transcription is not attempted.
- [ ] Voice screen behavior online is identical to Phase 3 (regression-free).
- [ ] New unit/widget test passes; existing voice tests (if any) still pass.
- [ ] Manual rehearsal #1, #2, #3 above all pass on the Pixel 7a.
- [ ] Dashboard: zero `RenderFlex overflowed` warnings in debug console during a top-to-bottom scroll with seeded data and with no data.
- [ ] No new dependencies in `pubspec.yaml`.
