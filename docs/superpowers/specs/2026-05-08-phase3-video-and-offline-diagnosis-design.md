# Phase 3 — Real Video Recording & Offline Video Diagnosis (Days 7–8)

**Status:** Draft for review.
**Predecessor:** Phase 2 ([2026-05-08-phase2-calendar-graph-notifications-design.md](2026-05-08-phase2-calendar-graph-notifications-design.md)).

**Context:** Two interlocked items from the original roadmap. Right now the "video" button in `scan_screen.dart` is a lie — it shows a recording timer UI, then on stop calls `takePicture()` and hands the still frame to the preview/diagnosis flow. Phase 3 makes it record an actual MP4 file, plays it back in preview, sends it through chat as a real video message, and runs offline disease diagnosis by sampling frames from the recorded file.

## Decisions baked in (please override on review if any are wrong)

| # | Decision | Default | Rationale |
|---|---|---|---|
| D1 | Container/codec | MP4 / H.264 (`camera` package's Android default) | Universal playback; works in `video_player` and `chewie` |
| D2 | Max recording length | **15 seconds**, auto-stop on timer | At ~1.2 Mbps H.264 ≈ 2.2 MB per clip — half the data/storage of 30s, still enough to pan over a leaf showing symptoms. |
| D3 | Frame-sampling strategy for diagnosis | Sample 5 frames at 0%, 25%, 50%, 75%, 100% of video duration after recording finishes | Post-recording extraction via the `video_thumbnail` package is reliable across Android API levels; sampling-during-recording would require interleaving `takePicture()` with `startVideoRecording()`, which is fragile in `camera` ^0.11 |
| D4 | Diagnosis aggregation | Take the **highest-confidence** detection across the 5 frames as the "primary" diagnosis | Plant-disease videos typically pan over symptoms — the single best frame is more diagnostic than an average of mediocre ones. Majority-vote is documented as a future-work alternative |
| D5 | Storage | Local: `<app docs>/videos/<uuid>.mp4`. Remote: same `video_url` field in `diagnoses`/`progress_updates`/`chat_messages.metadata` that the schema already exposes — populate with the local path until `sync_service` can upload | The schema already has `video_url TEXT` columns ([lib/data/local/database_helper.dart:110](../../../lib/data/local/database_helper.dart#L110), [:177](../../../lib/data/local/database_helper.dart#L177)); no schema change |
| D6 | Player package | `video_player: ^2.x` (Flutter team, official), wrapped with our own `_VideoPlayerView` widget | Most stable, no extra controls dependency. We can add `chewie` later if scrubbing UI needs grow |
| D7 | Frame-extraction package | `video_thumbnail: ^0.5.x` (or current stable) | Used by ~40k+ Flutter apps for thumbnail generation; works on Android without native build flags |
| D8 | Chat-display format | Thumbnail tile (poster frame + play overlay) inside the chat bubble; tap → fullscreen `_VideoPlayerView` | Matches the existing `image_url`-as-thumbnail pattern in `ChatMessageModel.metadata` |
| D9 | Video retention | Local video files auto-deleted after **30 days**. Cleanup runs on app start, gated to once per day via SharedPreferences. | One month covers most plant-disease treatment cycles (7–21 days) plus a buffer for follow-up reference. Cleanup-on-start avoids WorkManager / background-isolate complexity. |
| D10 | Expired-video UX | Show the poster frame indefinitely. When `videoUrl` is a tombstone (`expired:<original_filename>`), render an "expired" badge over the play overlay; tap shows a snackbar instead of opening the player. Diagnosis findings + treatment recs unchanged forever. | User chose "Show poster frame + 'video expired' badge". Diagnosis row keeps its visual breadcrumb of what was diagnosed. |
| D11 | Manual delete | Always-available trash icon in the fullscreen `_VideoPlayerView` app bar. Confirm dialog before deletion. Both auto-expiry and manual-delete write the same `expired:<original_filename>` tombstone — UI handles both identically. | Single code path, simple UX, can't accidentally tap. |
| D12 | Cleanup visibility | Fully invisible. No toast, no settings stat. Cleanup is silent on app start. | User chose this; matches the "set it and forget it" mental model of phone-photo lifecycle. |

## Constraints (carry-over)

- **No Supabase schema changes.** `video_url` columns exist; only client code touches them.
- **Android-primary, web fallback.** Web browsers can record video via the `camera` package's `MediaRecorder` API on supported browsers — but the focus is Android. iOS untested.
- **Defensive remote calls** continue using `_runOrFallback`.

## Goal

Two deliverables:

1. **Real video recording end-to-end:** Record button starts an actual MP4 capture; stop finalizes the file; preview screen plays it back; chat shows it as a video message. No more still-frame substitutes.

2. **Offline video diagnosis:** When the user proceeds from preview to "Yes, track it" (or auto-diagnose-on-continue), the app extracts 5 frames from the saved MP4, runs each through the existing `LocalClassifierService` TFLite pipeline, picks the highest-confidence detection, and writes a `DiagnosisModel` with `videoUrl: <local path>` to local SQLite. Treatment recommendations come from the local KB. Works in airplane mode.

## 3.1 Video Recording in Scan Screen

### Current bug
[lib/features/scan/scan_screen.dart:113–147](../../../lib/features/scan/scan_screen.dart#L113-L147) — `_toggleVideo` runs a UI-only timer and calls `takePicture()` on stop. No `startVideoRecording`/`stopVideoRecording` anywhere.

### New behavior
- **Start:** `await _controller!.prepareForVideoRecording()` then `await _controller!.startVideoRecording()`. Lock orientation, show "REC" pill, start a Timer that updates the visible duration AND auto-calls stop at 30 s.
- **Stop:** `final XFile videoFile = await _controller!.stopVideoRecording();`. The file is at `videoFile.path` — typically a temp directory, so immediately move it: `final saved = await _persistRecording(videoFile);` which copies into `${appDocs}/videos/<uuid>.mp4` and deletes the temp.
- **Open preview** with the saved video path. New `VideoPreviewScreen` replaces the image preview path when the file is a video.

### Permissions
The `camera` package already declares `RECORD_AUDIO` requirement. `enableAudio: true` (currently `enableAudio: !kIsWeb` — keep that, just verify the controller is reinitialised with audio enabled when entering video mode if needed).

### Edge cases
- User backgrounds the app mid-recording → on `AppLifecycleState.paused`, call `stopVideoRecording` and discard the file (don't try to recover).
- Disk full → catch `CameraException` from `startVideoRecording`, show snackbar "Not enough space to record."
- User taps stop within 1 second of start → still produces a valid file; don't reject for short duration.

## 3.2 VideoPreviewScreen

New file `lib/features/scan/video_preview_screen.dart`. Mirrors [preview_screen.dart](../../../lib/features/scan/preview_screen.dart)'s layout but renders a `VideoPlayer` with controls (play/pause, scrubber, mute) instead of `Image.memory`. Same "Retake" / "Continue" buttons.

`Continue` pushes `ScanResultScreen` with new constructor params:
- Drop the `imageBytes` requirement when `isFromVideo: true`.
- Add `videoFile: XFile?` and `posterFrameBytes: Uint8List?` (the 0%-time thumbnail, used by `ScanResultScreen` for the result card).

`ScanResultScreen` already accepts `imageFile` + `imageBytes`. Treat the poster frame as the `imageBytes` so the existing image-render path works for the diagnosis card. The actual video plays only on `VideoPreviewScreen` and inside chat bubbles — the result screen shows a poster, not a player (avoids autoplay distraction during the diagnosis result reveal).

## 3.3 Frame-Sampling Diagnosis Pipeline

New service `lib/services/video_diagnosis_service.dart`:

```dart
class VideoDiagnosisFrame {
  final int positionMs;       // sample timestamp
  final Uint8List jpegBytes;  // extracted frame
  final AiBackendDetectionItem? primary; // best detection from this frame, or null
}

class VideoDiagnosisResult {
  final List<VideoDiagnosisFrame> frames; // length 5, in time order
  final int bestFrameIndex;               // index of frame with highest confidence
  final AiBackendDetectionItem? bestDetection; // == frames[bestFrameIndex].primary
  final Duration videoDuration;
}

class VideoDiagnosisService {
  VideoDiagnosisService({required LocalClassifierService localClassifier});

  /// Sample 5 frames at 0/25/50/75/100% of duration, run each through TFLite,
  /// return the aggregated result with the best-confidence detection picked out.
  Future<VideoDiagnosisResult> analyzeVideo({
    required String videoFilePath,
    required CropType? cropTypeHint,
  });
}
```

Inside `analyzeVideo`:
1. Read video duration via `video_thumbnail` (or `video_player` controller, but thumbnail-only is lighter).
2. Compute 5 timestamps.
3. For each timestamp: `final bytes = await VideoThumbnail.thumbnailData(video: path, timeMs: t, imageFormat: ImageFormat.JPEG, quality: 85);`
4. For each frame: call existing `localClassifier.classifyImage(imageBytes: bytes, filename: 'frame_${i}.jpg', cropType: cropTypeHint)` — re-uses the TFLite pipeline that the still-photo path already exercises.
5. Pick the frame with the highest `primaryDetection.confidence`.
6. Return the `VideoDiagnosisResult`.

If `localClassifier.classifyImage` throws on every frame (e.g. TFLite asset missing), surface as an exception so `ScanResultScreen` can fall back to the existing `aiBackend.detectImage` path. Don't silently swallow.

### Tests
`test/services/video_diagnosis_service_test.dart` is **out of scope** for Phase 3 — TFLite + video file dependencies make unit testing infeasible without significant fixture work. Validation comes from the on-device manual rehearsal (Task 12). Document as a known gap; if time permits in Phase 4, add a unit test using a small fixture .mp4 in `test/fixtures/`.

## 3.4 ScanResultScreen Integration

[lib/features/scan/scan_result_screen.dart](../../../lib/features/scan/scan_result_screen.dart) currently calls `localClassifier.classifyImage(...)` first, then `aiBackend.detectImage(...)` as fallback. For video:

```dart
if (widget.isFromVideo && widget.videoFile != null) {
  // New path
  final result = await videoDiagnosisService.analyzeVideo(
    videoFilePath: widget.videoFile!.path,
    cropTypeHint: selectedCrop?.cropType,
  );
  detection = AiBackendDetectResponse(
    primaryDetection: result.bestDetection,
    detections: [if (result.bestDetection != null) result.bestDetection!],
    // …rest filled in from the best frame's classifier output
  );
} else {
  // Existing image path — unchanged
  detection = await localClassifier.classifyImage(...);
}
```

Wrap in the same `try/catch` so a video-diagnosis failure falls back to remote `aiBackend.detectImage` on the poster frame.

When tracking the diagnosis (`_trackDiagnosis`), persist `videoUrl: widget.videoFile!.path` into the `DiagnosisModel`. When sync runs and uploads succeed, `videoUrl` gets replaced with the remote URL.

## 3.5 Chat Display

[lib/features/chat/screens/chat_screen.dart](../../../lib/features/chat/screens/chat_screen.dart) currently renders attached images via `metadata['image_url']`. For videos:

- Sender writes `metadata['video_url'] = <local path or remote url>` and `metadata['video_poster_url'] = <poster frame path>` (a generated JPEG saved alongside the video).
- Bubble renderer: when `video_url` exists, show the poster frame with a play-circle overlay; tap → push fullscreen `_VideoPlayerView`.
- The existing image-display branch is unchanged.

The `_VideoPlayerView` is a new widget at `lib/features/chat/widgets/video_player_view.dart`: full-screen `Scaffold` with a back button and a `VideoPlayer` + simple controls (play/pause, mute, scrubber). Closes on back.

## 3.6 Video Lifecycle (Auto-Expire + Manual Delete)

### Storage model

- **Video file:** `<app docs>/videos/<uuid>.mp4` — large, transient.
- **Poster frame:** `<app docs>/videos/<uuid>.jpg` (or whatever `imageUrl` already does for the still-photo path) — small, kept indefinitely.
- **Diagnosis row** in SQLite — kept indefinitely. Only the `videoUrl` column is mutated when a video file is removed.

### Tombstone format

When a video file is deleted (auto OR manual), set `videoUrl = 'expired:<original_basename>'` (e.g. `expired:7f3c-1a2b.mp4`). This:

1. Lets UI detect "this row USED to have a video" without needing a schema column.
2. Reuses the existing `videoUrl TEXT` column — no migration.
3. Survives sync (the tombstone string round-trips through Supabase as plain text).

UI rule:
- `videoUrl == null` → no video ever attached → render still image only.
- `videoUrl?.startsWith('expired:') == true` → tombstone → render poster + "Video expired" badge over the play overlay; tap → snackbar "This video is no longer available."
- otherwise → live video → render poster + play overlay; tap → `_VideoPlayerView`.

### Auto-expire (cleanup service)

New file: `lib/services/video_cleanup_service.dart`.

```dart
class VideoCleanupService {
  VideoCleanupService({required DatabaseHelper db});

  /// Run once per day on app start. Sweeps `<app docs>/videos/` for files
  /// older than 30 days, deletes them, and rewrites their videoUrl to a
  /// tombstone in:
  ///   - diagnoses.video_url
  ///   - progress_updates.video_url
  ///   - chat_messages.metadata.video_url (JSON-encoded; rewrite the JSON)
  /// Idempotent. Catches and logs per-file errors without aborting the sweep.
  Future<VideoCleanupReport> runIfDue();

  static const Duration retention = Duration(days: 30);
  static const String _lastRunKey = 'video_cleanup_last_run_iso8601';
}

class VideoCleanupReport {
  final int filesDeleted;
  final int rowsTombstoned;
  final List<String> errors;
}
```

Call site: in `_CropCareAppState.initState` (the StatefulWidget from Phase 2 Task 9), schedule a `WidgetsBinding.instance.addPostFrameCallback` that calls `VideoCleanupService(db: ...).runIfDue()` and discards the result. Fire-and-forget — UI never blocks on cleanup.

Daily-gate logic:
```dart
final prefs = await SharedPreferences.getInstance();
final lastRun = DateTime.tryParse(prefs.getString(_lastRunKey) ?? '');
if (lastRun != null && DateTime.now().difference(lastRun) < const Duration(hours: 23)) {
  return VideoCleanupReport(filesDeleted: 0, rowsTombstoned: 0, errors: []);
}
// …sweep…
await prefs.setString(_lastRunKey, DateTime.now().toIso8601String());
```

The 23-hour gate (instead of strict day-boundary) ensures the cleanup runs once on the first app launch each day even if the user opens the app at 11:55 PM and again at 8 AM next morning.

### Manual delete

In `_VideoPlayerView` (the new fullscreen player widget), the app bar gets a trash icon:

```dart
AppBar(
  actions: [
    IconButton(
      icon: const Icon(Icons.delete_outline),
      onPressed: () async {
        final confirmed = await showDialog<bool>(...); // "Delete this video? Diagnosis details will be kept."
        if (confirmed == true) {
          await VideoCleanupService(db: ...).deleteVideo(widget.videoPath);
          if (mounted) Navigator.of(context).pop();
        }
      },
    ),
  ],
);
```

`deleteVideo(String path)` is a public method on `VideoCleanupService` — same logic as the auto-sweep but operating on a single file. Both code paths share the same tombstone helper.

### Tests

`test/services/video_cleanup_service_test.dart`:
- "Run is gated to once per 23 hours" — mock SharedPreferences, verify second call within 23h returns early.
- "Files older than 30 days get deleted; newer files survive" — set up a temp dir with files of varying mtimes, run cleanup, assert which remain.
- "DB rows with matching videoUrl get tombstoned" — seed in-memory SQLite, run cleanup, assert column rewrites.
- "Per-file errors don't abort the sweep" — make one file undeletable (mock file system), verify report includes error and other files were still processed.

(`SharedPreferences.setMockInitialValues({})` and `path_provider_platform_interface` mocks make this testable on the host without an emulator.)

## 3.7 Offline Behavior

Already mostly works because:
- TFLite is local — no network required for diagnosis.
- Disease KB is in local SQLite — no network required for treatment lookup.
- Local video file lives in app documents — no network required for storage.

The only network-dependent step is **uploading** the video to Supabase Storage. That's fully deferred to `sync_service` (which already syncs `diagnoses` rows). When `sync_service` sees a `DiagnosisModel.videoUrl` that's a local path, it should upload the file and rewrite the field with the remote URL. **Phase 3 implements only the local write path; the upload-on-sync extension is a separate sync_service edit listed at the bottom.**

## Out of scope for Phase 3

- Real-time video diagnosis (running TFLite on every preview frame during recording). The 5-frame post-recording sample is the demo target.
- Video editing (trim, rotate, filter).
- Multi-video playlist or thumbnail grid in chat.
- iOS-specific encoding tweaks.
- Background uploading via WorkManager.

## Definition of Done

- [ ] `_toggleVideo` actually records an MP4 via `startVideoRecording`/`stopVideoRecording`. Auto-stops at **15 s**.
- [ ] Recorded file is moved out of temp into `<app docs>/videos/<uuid>.mp4` and the path is passed forward.
- [ ] `VideoPreviewScreen` plays the recorded video before continuing.
- [ ] `VideoDiagnosisService.analyzeVideo` extracts 5 frames, runs them through the local TFLite, and returns the best-confidence detection.
- [ ] `ScanResultScreen` runs the video pipeline when `isFromVideo && videoFile != null`, falls back to remote detection on the poster frame on failure.
- [ ] `DiagnosisModel.videoUrl` is populated on save.
- [ ] Chat bubbles render attached videos as a poster + play overlay; tap opens fullscreen player.
- [ ] `_VideoPlayerView` app bar has a trash icon → confirm dialog → deletes the file and writes the `expired:<filename>` tombstone.
- [ ] `VideoCleanupService.runIfDue` runs on app start (fire-and-forget), gated to once per 23 hours, and tombstones any video older than 30 days.
- [ ] UI correctly distinguishes the three states of `videoUrl`: null (no video ever), `expired:` tombstone (poster + "Video expired" badge), live path/URL (poster + play overlay).
- [ ] `VideoCleanupService` unit tests pass (gating, age threshold, tombstone writes, error tolerance).
- [ ] `flutter analyze` clean (no new errors).
- [ ] All existing unit tests still pass.
- [ ] Manual on-device rehearsal: record a 15-second clip in airplane mode → preview plays → continue → diagnosis result shows with treatment steps → tracked diagnosis appears in History → chat that uses the video shows playable thumbnail → manual-delete from fullscreen player flips the bubble to "Video expired" badge.

## Files this phase will touch

**New:**
- `lib/services/video_diagnosis_service.dart`
- `lib/services/video_cleanup_service.dart`
- `lib/features/scan/video_preview_screen.dart`
- `lib/features/chat/widgets/video_player_view.dart`
- `test/services/video_cleanup_service_test.dart`

**Modified:**
- `pubspec.yaml` (add `video_player`, `video_thumbnail`)
- `lib/features/scan/scan_screen.dart` (`_toggleVideo` rewrite + `_persistRecording` helper, **15-second auto-stop**)
- `lib/features/scan/preview_screen.dart` (route video files to the new `VideoPreviewScreen` instead)
- `lib/features/scan/scan_result_screen.dart` (video-mode branch in `_analyze`, accepts `videoFile` + `posterFrameBytes`)
- `lib/features/chat/screens/chat_screen.dart` (render `metadata['video_url']`: handle three states — null, `expired:` tombstone, live URL)
- `lib/features/chat/providers/chat_provider.dart` (write `video_url`/`video_poster_url` into outgoing message metadata)
- `lib/features/scan/diagnostic_history_screen.dart` (handle `expired:` tombstone in `videoUrl` for video-source diagnoses — show "Video expired" hint instead of play affordance)
- `lib/app.dart` (in `_CropCareAppState.initState`, fire-and-forget `VideoCleanupService(db: ...).runIfDue()` after the existing tap-stream subscription)

**Conditionally modified (sync layer — separate sub-task at end of Phase 3):**
- `lib/services/sync_service.dart` (when uploading a `DiagnosisModel`, if `videoUrl` is a local path, upload to Supabase Storage `crop-videos` bucket and rewrite the field). This is a "nice to have" for Phase 3; the demo can run with local-only video paths if Supabase Storage isn't pre-configured. Document as a known limitation if not implemented.

## Sequencing within Phase 3

| Day | Tasks |
|---|---|
| 7 morning | `pubspec.yaml` packages + `_toggleVideo` rewrite (real recording). Manual smoke: record a clip on Android, verify the file plays in `adb shell am start -d file://...` |
| 7 afternoon | `VideoPreviewScreen` with `video_player` controller. Wire from scan flow. |
| 8 morning | `VideoDiagnosisService.analyzeVideo` (5-frame sampling). Wire into `ScanResultScreen`. |
| 8 afternoon | Chat-side video display + provider metadata. **`VideoCleanupService` (auto-expire + manual delete) + tests + wire into `app.dart`.** On-device rehearsal end-to-end. Optional: sync_service upload extension if time permits. |
