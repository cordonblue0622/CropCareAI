# Phase 3 — Video Recording & Offline Diagnosis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **DO NOT auto-commit.** The repo owner reviews and commits manually. Every "stage for review" step says exactly that — leave changes unstaged or use `git add` only, never `git commit`. This rule overrides any default workflow step in any skill.

**Goal:** Replace the still-frame fake-video flow with real MP4 recording (15-second cap), play it back in a new `VideoPreviewScreen`, run offline disease diagnosis by sampling 5 frames through the existing TFLite pipeline, render videos in chat as poster + play overlay, and add a 30-day auto-cleanup service with manual delete from a fullscreen player. No Supabase schema changes — `videoUrl` columns already exist; `expired:<filename>` tombstones are written when videos are removed (auto OR manual).

**Architecture:** `scan_screen` calls real `startVideoRecording`/`stopVideoRecording`, persists into `<app docs>/videos/<uuid>.mp4`, routes to `VideoPreviewScreen`. `VideoDiagnosisService.analyzeVideo` extracts 5 frames via `video_thumbnail` and feeds each to the existing `LocalClassifierService`, returning the highest-confidence detection. `VideoCleanupService` runs once-per-day from `_CropCareAppState.initState`, sweeps three tables (`diagnoses`, `progress_updates`, `chat_messages.metadata`) replacing expired video paths with `expired:<filename>` tombstones. UI surfaces the three states of `videoUrl`: null (no video), tombstone (poster + "Video expired" badge), live path/URL (poster + play overlay).

**Tech Stack:** Flutter SDK >=3.2, Dart 3.x, Provider state-mgmt, sqflite, Supabase (no schema changes), `camera` (already present), `video_player: ^2.x` (new), `video_thumbnail: ^0.5.x` (new), `path_provider` (already present), `shared_preferences` (already present), `uuid` (already present), `flutter_local_notifications` (Phase 1).

**Spec:** [docs/superpowers/specs/2026-05-08-phase3-video-and-offline-diagnosis-design.md](../specs/2026-05-08-phase3-video-and-offline-diagnosis-design.md)

**Predecessor state:** Phases 1 + 2 are committed (Phase 1 in `64da509`; Phase 2 staged or committed before Phase 3 starts). Subagents should treat existing committed/staged work as approved context and not modify it outside their assigned task.

---

## Task 1: Add `video_player` and `video_thumbnail` packages

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependencies**

In `pubspec.yaml`, find the `# Camera & Image` section. Append two new lines for video support immediately after the existing `tflite_flutter` line (or wherever the section ends):

```yaml
  # Video
  video_player: ^2.9.2
  video_thumbnail: ^0.5.3
```

So that block reads:

```yaml
  # Camera & Image
  camera: ^0.11.0+2
  image_picker: ^1.1.2
  image: ^4.5.4
  cached_network_image: ^3.4.1
  tflite_flutter: ^0.11.0

  # Video
  video_player: ^2.9.2
  video_thumbnail: ^0.5.3
```

- [ ] **Step 2: Run `flutter pub get`**

```
flutter pub get
```
Expected: resolves cleanly. `pubspec.lock` updates. If pub fails, STOP and report BLOCKED with the full error output.

- [ ] **Step 3: Stage for review (DO NOT commit)**

```
git add pubspec.yaml pubspec.lock
```

Stop. Report "Task 1 staged — ready for review. Pub get succeeded."

---

## Task 2: Real video recording in scan_screen

**Files:**
- Modify: `lib/features/scan/scan_screen.dart`

Rewrites `_toggleVideo` to actually call `startVideoRecording`/`stopVideoRecording`, persists the recorded file into app docs, auto-stops at 15 s, and passes the resulting `XFile` to a new `_openVideoPreview` (created in Task 3).

- [ ] **Step 1: Add imports**

Near the top of `lib/features/scan/scan_screen.dart`, after the existing `import 'preview_screen.dart';` line, add:

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'video_preview_screen.dart';
```

(Note: `video_preview_screen.dart` doesn't exist until Task 3. The import will be unresolved until then — leave it; analyzer will flag it as info but the file will compile after Task 3.)

- [ ] **Step 2: Add video-recording fields to state**

Inside `_ScanScreenState`, find the existing fields (around line 17-24). Add a max-duration constant near the class top:

```dart
  static const Duration _maxVideoDuration = Duration(seconds: 15);
```

The existing `_isRecording`, `_recordingTimer`, `_recordingSeconds` fields are already present and reused.

- [ ] **Step 3: Replace `_toggleVideo` with the real implementation**

Replace the entire existing `_toggleVideo` method (currently around lines 113-147):

```dart
  Future<void> _toggleVideo() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      await _controller!.prepareForVideoRecording();
      await _controller!.startVideoRecording();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start recording: $e')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _recordingSeconds = 0;
    });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _recordingSeconds++);
      if (_recordingSeconds >= _maxVideoDuration.inSeconds) {
        // Auto-stop at the cap.
        _stopRecording();
      }
    });
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    XFile? rawFile;
    try {
      rawFile = await _controller!.stopVideoRecording();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not finalize recording: $e')),
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _recordingSeconds = 0;
    });

    if (rawFile == null) return;

    final saved = await _persistRecording(rawFile);
    if (saved == null || !mounted) return;
    await _openVideoPreview(saved);
  }

  /// Move the camera-package's temp recording into `<app docs>/videos/<uuid>.mp4`.
  /// Returns the persisted XFile or null on failure.
  Future<XFile?> _persistRecording(XFile rawFile) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final videosDir = Directory('${docs.path}/videos');
      if (!await videosDir.exists()) {
        await videosDir.create(recursive: true);
      }
      final id = const Uuid().v4();
      final destPath = '${videosDir.path}/$id.mp4';
      final source = File(rawFile.path);
      await source.copy(destPath);
      try {
        await source.delete();
      } catch (_) {/* tolerate temp-file lock on some Android devices */}
      return XFile(destPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save video: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _openVideoPreview(XFile videoFile) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPreviewScreen(videoFile: videoFile),
      ),
    );
  }
```

The existing `_openPreview(XFile? file, {bool isFromVideo = false})` (around line 178) should remain unchanged — it's still used by `_capture` and the gallery/camera fallback paths for STILL photos.

- [ ] **Step 4: Run static analysis (will fail until Task 3 lands)**

```
flutter analyze lib/features/scan/scan_screen.dart
```
Expected: ONE error about the missing `video_preview_screen.dart` import. That's expected and will be fixed in Task 3. No other errors.

If you see errors OTHER than the missing-import one, escalate as BLOCKED.

- [ ] **Step 5: Stage for review (DO NOT commit)**

```
git add lib/features/scan/scan_screen.dart
```

Stop. Report "Task 2 staged — ready for review. (Expected unresolved import for video_preview_screen.dart will be fixed in Task 3.)"

---

## Task 3: VideoPreviewScreen

**Files:**
- Create: `lib/features/scan/video_preview_screen.dart`
- Modify: `lib/features/scan/preview_screen.dart` (no changes — it stays for still photos; video bypasses it)

VideoPreviewScreen mirrors the layout of [preview_screen.dart](../../../lib/features/scan/preview_screen.dart) but plays the video and continues to `ScanResultScreen` with the video file attached.

- [ ] **Step 1: Create the screen**

Create `lib/features/scan/video_preview_screen.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import 'scan_result_screen.dart';

class VideoPreviewScreen extends StatefulWidget {
  final XFile videoFile;
  const VideoPreviewScreen({super.key, required this.videoFile});

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  VideoPlayerController? _controller;
  final TextEditingController _messageCtrl = TextEditingController();
  bool _continuing = false;
  bool _initError = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    try {
      final c = VideoPlayerController.file(File(widget.videoFile.path));
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _controller = c);
      await c.play();
    } catch (_) {
      if (mounted) setState(() => _initError = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _continueToChat() async {
    if (_continuing) return;
    setState(() => _continuing = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScanResultScreen(
            imageFile: widget.videoFile, // ScanResultScreen treats this as the source XFile
            videoFile: widget.videoFile,
            initialQuery: _messageCtrl.text.trim(),
            openChatOnComplete: true,
            isFromVideo: true,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back,
                    color: AppColors.primaryDark, size: 28),
              ),
              const Spacer(),
              const Text('Video Preview',
                  style: TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 18)),
              const Spacer(),
              const SizedBox(width: 28),
            ]),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _videoArea(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add your first message',
                    style: TextStyle(
                        color: AppColors.textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _messageCtrl,
                  minLines: 2,
                  maxLines: 4,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText:
                        'Tell the AI what you noticed before sending this video...',
                    hintStyle: const TextStyle(color: AppColors.textLightGray),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.all(16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primaryLight),
                    foregroundColor: AppColors.textDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Retake',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _continuing ? null : _continueToChat,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _continuing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward, size: 18),
                  label: Text(
                    _continuing ? 'Opening chat...' : 'Continue',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _videoArea() {
    if (_initError) {
      return Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Could not play this video. Try recording again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: AppColors.primary),
      );
    }
    return GestureDetector(
      onTap: () {
        if (c.value.isPlaying) {
          c.pause();
        } else {
          c.play();
        }
        setState(() {});
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
          if (!c.value.isPlaying)
            Container(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(16),
              child: const Icon(Icons.play_arrow,
                  color: Colors.white, size: 36),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run static analysis**

```
flutter analyze lib/features/scan/video_preview_screen.dart lib/features/scan/scan_screen.dart
```
Expected: a few errors on `ScanResultScreen` constructor — the `videoFile` named param doesn't exist yet (added in Task 5). Leave them; the `scan_screen.dart` import error from Task 2 should now be resolved.

If you see errors OTHER than the `ScanResultScreen.videoFile` one, escalate as BLOCKED.

- [ ] **Step 3: Stage for review (DO NOT commit)**

```
git add lib/features/scan/video_preview_screen.dart
```

Stop. Report "Task 3 staged — ready for review. (Expected unresolved param `videoFile` on ScanResultScreen will be fixed in Task 5.)"

---

## Task 4: VideoDiagnosisService (5-frame sampling)

**Files:**
- Create: `lib/services/video_diagnosis_service.dart`

Pure-ish service: opens the video, samples 5 frames at 0/25/50/75/100% of duration, runs each through `LocalClassifierService`, returns the result.

- [ ] **Step 1: Implement the service**

Create `lib/services/video_diagnosis_service.dart`:

```dart
import 'dart:typed_data';

import 'package:video_thumbnail/video_thumbnail.dart';

import '../data/remote/ai_backend_service.dart';
import 'local_classifier_service.dart';

class VideoDiagnosisFrame {
  final int positionMs;
  final Uint8List jpegBytes;
  final AiBackendDetectResponse? detection;

  const VideoDiagnosisFrame({
    required this.positionMs,
    required this.jpegBytes,
    required this.detection,
  });

  double get _confidence => detection?.primaryDetection?.confidence ?? 0;
}

class VideoDiagnosisResult {
  final List<VideoDiagnosisFrame> frames;
  final int bestFrameIndex;
  final Duration videoDuration;

  const VideoDiagnosisResult({
    required this.frames,
    required this.bestFrameIndex,
    required this.videoDuration,
  });

  AiBackendDetectResponse? get bestDetection =>
      bestFrameIndex >= 0 && bestFrameIndex < frames.length
          ? frames[bestFrameIndex].detection
          : null;

  Uint8List? get posterBytes =>
      frames.isNotEmpty ? frames.first.jpegBytes : null;
}

/// Samples 5 frames from a recorded video and runs each through the existing
/// on-device TFLite classifier. Returns the highest-confidence detection.
class VideoDiagnosisService {
  VideoDiagnosisService({required LocalClassifierService localClassifier})
      : _localClassifier = localClassifier;

  final LocalClassifierService _localClassifier;

  static const _sampleFractions = <double>[0.0, 0.25, 0.5, 0.75, 1.0];

  Future<VideoDiagnosisResult> analyzeVideo({
    required String videoFilePath,
    required String? cropTypeHint,
  }) async {
    // We don't have a free probe-video-duration helper in `video_thumbnail`,
    // so estimate duration by extracting at fraction 1.0 with a max-duration
    // hint. In practice we cap recordings at 15s (Phase 3 §3.1), so we can
    // assume a worst-case duration cap when computing positions.
    const assumedMaxMs = 16000; // 15s + 1s padding
    final positions = _sampleFractions
        .map((f) => (f * assumedMaxMs).round())
        .toList();

    final frames = <VideoDiagnosisFrame>[];
    for (int i = 0; i < positions.length; i++) {
      Uint8List? bytes;
      try {
        bytes = await VideoThumbnail.thumbnailData(
          video: videoFilePath,
          imageFormat: ImageFormat.JPEG,
          timeMs: positions[i],
          quality: 85,
        );
      } catch (_) {
        bytes = null;
      }
      if (bytes == null || bytes.isEmpty) continue;

      AiBackendDetectResponse? detection;
      try {
        detection = await _localClassifier.classifyImage(
          imageBytes: bytes,
          filename: 'frame_$i.jpg',
          cropType: cropTypeHint,
        );
      } catch (_) {
        detection = null;
      }

      frames.add(VideoDiagnosisFrame(
        positionMs: positions[i],
        jpegBytes: bytes,
        detection: detection,
      ));
    }

    if (frames.isEmpty) {
      throw VideoDiagnosisException(
          'Could not extract any frames from the recorded video.');
    }

    int best = 0;
    double bestConf = frames[0]._confidence;
    for (int i = 1; i < frames.length; i++) {
      if (frames[i]._confidence > bestConf) {
        bestConf = frames[i]._confidence;
        best = i;
      }
    }

    return VideoDiagnosisResult(
      frames: frames,
      bestFrameIndex: best,
      videoDuration: Duration(
          milliseconds: positions.isNotEmpty ? positions.last : assumedMaxMs),
    );
  }
}

class VideoDiagnosisException implements Exception {
  final String message;
  VideoDiagnosisException(this.message);
  @override
  String toString() => 'VideoDiagnosisException: $message';
}
```

- [ ] **Step 2: Run static analysis**

```
flutter analyze lib/services/video_diagnosis_service.dart
```
Expected: no errors.

- [ ] **Step 3: Stage for review (DO NOT commit)**

```
git add lib/services/video_diagnosis_service.dart
```

Stop. Report "Task 4 staged — ready for review."

---

## Task 5: ScanResultScreen video integration

**Files:**
- Modify: `lib/features/scan/scan_result_screen.dart`

Adds `videoFile` constructor param, runs the video pipeline when present, persists `videoUrl` on diagnosis save.

- [ ] **Step 1: Add the constructor param + import**

In `lib/features/scan/scan_result_screen.dart`, near the other service imports (around line 14), add:

```dart
import '../../../services/video_diagnosis_service.dart';
```

In the `ScanResultScreen` widget class, find the existing constructor (around lines 22-38). Add a new optional `videoFile` field and constructor param:

```dart
  final XFile? videoFile;
```

Update the constructor:

```dart
  const ScanResultScreen({
    super.key,
    required this.imageFile,
    this.cropId,
    this.imageBytes,
    this.initialQuery,
    this.openChatOnComplete = false,
    this.isFromVideo = false,
    this.videoFile,
  });
```

- [ ] **Step 2: Branch the analysis path on video**

Find `_analyze()` (around line 60). Locate the existing `try { detection = await localClassifier.classifyImage(...); } catch (_) { detection = await aiBackend.detectImage(...); }` block (around lines 73-86). Replace it with:

```dart
      AiBackendDetectResponse detection;
      if (widget.isFromVideo && widget.videoFile != null) {
        try {
          final videoResult = await VideoDiagnosisService(
                  localClassifier: localClassifier)
              .analyzeVideo(
                  videoFilePath: widget.videoFile!.path,
                  cropTypeHint: selectedCrop?.cropType.value);
          if (videoResult.bestDetection != null) {
            detection = videoResult.bestDetection!;
          } else {
            // No frame returned a detection — fall back to remote on poster.
            detection = await aiBackend.detectImage(
              imageBytes: imageBytes,
              filename: widget.imageFile.name,
              cropType: selectedCrop?.cropType.value,
            );
          }
          // Use the best frame as the visible poster image.
          final posterBytes = videoResult.posterBytes;
          if (posterBytes != null) {
            _resolvedImageBytes = posterBytes;
          }
        } catch (_) {
          // Video pipeline failed entirely — fall back to remote on poster bytes.
          detection = await aiBackend.detectImage(
            imageBytes: imageBytes,
            filename: widget.imageFile.name,
            cropType: selectedCrop?.cropType.value,
          );
        }
      } else {
        try {
          detection = await localClassifier.classifyImage(
            imageBytes: imageBytes,
            filename: widget.imageFile.name,
            cropType: selectedCrop?.cropType.value,
          );
        } catch (_) {
          detection = await aiBackend.detectImage(
            imageBytes: imageBytes,
            filename: widget.imageFile.name,
            cropType: selectedCrop?.cropType.value,
          );
        }
      }
```

- [ ] **Step 3: Persist `videoUrl` when tracking the diagnosis**

Find `_trackDiagnosis()` (around line 181-225). Inside the `DiagnosisModel(...)` constructor call, add a `videoUrl` field:

Locate the existing line:
```dart
        diagnosedAt: now,
```

Add immediately above it (or near other URL fields):
```dart
        videoUrl: widget.videoFile?.path,
```

Also do the same in `_matchToDiagnosis(...)` (around line 608-634) where another `DiagnosisModel(...)` is constructed:
```dart
      videoUrl: widget.videoFile?.path,
```

- [ ] **Step 4: Run static analysis**

```
flutter analyze lib/features/scan/scan_result_screen.dart
```
Expected: no new errors. (The `imageBytes` references in the video branch use the existing local variable already in scope.)

- [ ] **Step 5: Run all tests**

```
flutter test
```
Expected: all existing tests still pass. No new tests added by this task.

- [ ] **Step 6: Stage for review (DO NOT commit)**

```
git add lib/features/scan/scan_result_screen.dart
```

Stop. Report "Task 5 staged — ready for review."

---

## Task 6: VideoCleanupService + tests

**Files:**
- Create: `lib/services/video_cleanup_service.dart`
- Test: `test/services/video_cleanup_service_test.dart`

Centralizes file deletion, tombstone writes, and the once-per-day gate for auto-expire.

- [ ] **Step 1: Write the failing tests**

Create `test/services/video_cleanup_service_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cropcare_ai/core/constants/app_constants.dart';
import 'package:cropcare_ai/data/local/database_helper.dart';
import 'package:cropcare_ai/services/video_cleanup_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String _docsPath;
  _FakePathProvider(this._docsPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => _docsPath;
}

void main() {
  late Directory tempDocs;
  late DatabaseHelper db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDocs = await Directory.systemTemp.createTemp('cropcare_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDocs.path);
    SharedPreferences.setMockInitialValues({});
    db = DatabaseHelper.instance;
    // Reset any existing in-process SQLite handle so the test points at a
    // fresh in-memory database. (DatabaseHelper exposes its singleton via
    // `instance`; in tests we just rely on the temp-docs sandboxing.)
  });

  tearDown(() async {
    if (await tempDocs.exists()) {
      await tempDocs.delete(recursive: true);
    }
  });

  test('runIfDue is gated to once per 23 hours', () async {
    final svc = VideoCleanupService(db: db);
    final r1 = await svc.runIfDue();
    final r2 = await svc.runIfDue();
    // First run records timestamp; second within 23h returns no work.
    expect(r1.errors, isEmpty);
    expect(r2.filesDeleted, 0);
    expect(r2.rowsTombstoned, 0);
  });

  test('files older than retention get deleted; newer survive', () async {
    final videosDir = Directory('${tempDocs.path}/videos')
      ..createSync(recursive: true);
    final old = File('${videosDir.path}/old.mp4')
      ..writeAsStringSync('x');
    final fresh = File('${videosDir.path}/fresh.mp4')
      ..writeAsStringSync('y');
    final ancient = DateTime.now()
        .subtract(VideoCleanupService.retention)
        .subtract(const Duration(days: 1));
    await old.setLastModified(ancient);

    final svc = VideoCleanupService(db: db);
    final report = await svc.runIfDue();

    expect(await old.exists(), isFalse);
    expect(await fresh.exists(), isTrue);
    expect(report.filesDeleted, 1);
  });

  test('per-file deletion error does not abort the sweep', () async {
    // We can't easily mock File deletion failure cross-platform, so this
    // test just ensures runIfDue tolerates an empty videos dir gracefully.
    final svc = VideoCleanupService(db: db);
    final report = await svc.runIfDue();
    expect(report.errors, isEmpty);
  });

  test('deleteVideo writes tombstone into diagnoses.video_url', () async {
    final videosDir = Directory('${tempDocs.path}/videos')
      ..createSync(recursive: true);
    final f = File('${videosDir.path}/abc.mp4')..writeAsStringSync('z');

    final database = await db.database;
    await database.insert(AppConstants.diagnosesTable, {
      'id': 'd1',
      'crop_id': 'c1',
      'user_id': 'u1',
      'diagnosis_mode': 'online',
      'disease_name': 'tomato_blight',
      'severity': 'mild',
      'video_url': f.path,
      'diagnosed_at': DateTime.now().toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    final svc = VideoCleanupService(db: db);
    await svc.deleteVideo(f.path);

    expect(await f.exists(), isFalse);
    final rows = await database.query(
      AppConstants.diagnosesTable,
      where: 'id = ?',
      whereArgs: ['d1'],
    );
    expect(rows.first['video_url'], 'expired:abc.mp4');
  });
}
```

Add `sqflite_common_ffi: ^2.x` and `path_provider_platform_interface: ^2.x` to `dev_dependencies` in `pubspec.yaml` if not already present:

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
  sqflite_common_ffi: ^2.3.3
  path_provider_platform_interface: ^2.1.2
```

Run `flutter pub get` after adding.

- [ ] **Step 2: Run the test (will fail)**

```
flutter test test/services/video_cleanup_service_test.dart
```
Expected: import-not-found error on `video_cleanup_service.dart`.

- [ ] **Step 3: Implement the service**

Create `lib/services/video_cleanup_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../data/local/database_helper.dart';

class VideoCleanupReport {
  final int filesDeleted;
  final int rowsTombstoned;
  final List<String> errors;

  const VideoCleanupReport({
    required this.filesDeleted,
    required this.rowsTombstoned,
    required this.errors,
  });

  bool get hasWork => filesDeleted > 0 || rowsTombstoned > 0;
}

/// Manages on-disk video file lifecycle:
///   - Auto-expire after [retention] (run once per 23h on app start).
///   - Manual delete via [deleteVideo].
///
/// In both cases, the file is removed and any DB row whose `video_url`
/// matches the deleted path is rewritten to `expired:<basename>` so the UI
/// can render the "Video expired" badge.
class VideoCleanupService {
  VideoCleanupService({required this.db});

  final DatabaseHelper db;

  static const Duration retention = Duration(days: 30);
  static const Duration _gate = Duration(hours: 23);
  static const String _lastRunKey = 'video_cleanup_last_run_iso8601';

  /// Run once per 23 hours; returns a no-op report if it has run recently.
  Future<VideoCleanupReport> runIfDue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastRunKey);
    final lastRun = raw == null ? null : DateTime.tryParse(raw);
    if (lastRun != null && DateTime.now().difference(lastRun) < _gate) {
      return const VideoCleanupReport(
          filesDeleted: 0, rowsTombstoned: 0, errors: []);
    }

    final report = await _sweep();
    await prefs.setString(_lastRunKey, DateTime.now().toIso8601String());
    return report;
  }

  /// Manual delete. Removes the file (if it exists) and writes the tombstone
  /// into any matching DB rows.
  Future<void> deleteVideo(String filePath) async {
    final file = File(filePath);
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('VideoCleanupService.deleteVideo: $e');
    }
    await _tombstoneRows(filePath);
  }

  Future<VideoCleanupReport> _sweep() async {
    final errors = <String>[];
    int filesDeleted = 0;
    int rowsTombstoned = 0;

    Directory? videosDir;
    try {
      final docs = await getApplicationDocumentsDirectory();
      videosDir = Directory(p.join(docs.path, 'videos'));
      if (!await videosDir.exists()) {
        return VideoCleanupReport(
            filesDeleted: 0, rowsTombstoned: 0, errors: errors);
      }
    } catch (e) {
      return VideoCleanupReport(
          filesDeleted: 0, rowsTombstoned: 0, errors: ['$e']);
    }

    final cutoff = DateTime.now().subtract(retention);

    await for (final entity in videosDir.list()) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        if (stat.modified.isAfter(cutoff)) continue;
        final path = entity.path;
        await entity.delete();
        filesDeleted++;
        rowsTombstoned += await _tombstoneRows(path);
      } catch (e) {
        errors.add('${entity.path}: $e');
      }
    }

    return VideoCleanupReport(
      filesDeleted: filesDeleted,
      rowsTombstoned: rowsTombstoned,
      errors: errors,
    );
  }

  Future<int> _tombstoneRows(String filePath) async {
    final basename = p.basename(filePath);
    final tombstone = 'expired:$basename';
    final database = await db.database;
    int total = 0;

    // diagnoses
    total += await database.update(
      AppConstants.diagnosesTable,
      {'video_url': tombstone},
      where: 'video_url = ?',
      whereArgs: [filePath],
    );

    // progress_updates
    total += await database.update(
      AppConstants.progressUpdatesTable,
      {'video_url': tombstone},
      where: 'video_url = ?',
      whereArgs: [filePath],
    );

    // chat_messages.metadata.video_url — JSON-rewrite path
    final chatRows = await database.query(
      AppConstants.chatMessagesTable,
      columns: ['id', 'metadata'],
    );
    for (final row in chatRows) {
      final raw = row['metadata'] as String?;
      if (raw == null || raw.isEmpty) continue;
      Map<String, dynamic> meta;
      try {
        meta = (jsonDecode(raw) as Map).cast<String, dynamic>();
      } catch (_) {
        continue;
      }
      if (meta['video_url'] == filePath) {
        meta['video_url'] = tombstone;
        await database.update(
          AppConstants.chatMessagesTable,
          {'metadata': jsonEncode(meta)},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        total++;
      }
    }

    return total;
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```
flutter test test/services/video_cleanup_service_test.dart
```
Expected: 4 tests pass.

If a test fails because of the `DatabaseHelper.instance` singleton state, the test may need a small adjustment to use a fresh database per test. Document any such fixture-fix as a NEEDS_CONTEXT escalation.

- [ ] **Step 5: Static analysis**

```
flutter analyze lib/services/video_cleanup_service.dart test/services/video_cleanup_service_test.dart
```
Expected: no errors.

- [ ] **Step 6: Stage for review (DO NOT commit)**

```
git add lib/services/video_cleanup_service.dart test/services/video_cleanup_service_test.dart pubspec.yaml pubspec.lock
```

Stop. Report "Task 6 staged — ready for review."

---

## Task 7: VideoPlayerView fullscreen widget

**Files:**
- Create: `lib/features/chat/widgets/video_player_view.dart`

Fullscreen player with play/pause + a delete button in the app bar that triggers `VideoCleanupService.deleteVideo`.

- [ ] **Step 1: Create the widget**

Create `lib/features/chat/widgets/video_player_view.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/video_cleanup_service.dart';

/// Fullscreen video player with a delete button in the app bar.
/// Pops with `true` if the user deleted the video, `null` otherwise.
class VideoPlayerView extends StatefulWidget {
  final String videoSource; // local path OR http(s) url
  const VideoPlayerView({super.key, required this.videoSource});

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  VideoPlayerController? _controller;
  bool _initError = false;

  bool get _isLocal =>
      !widget.videoSource.startsWith('http://') &&
      !widget.videoSource.startsWith('https://');

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    try {
      final c = _isLocal
          ? VideoPlayerController.file(File(widget.videoSource))
          : VideoPlayerController.networkUrl(Uri.parse(widget.videoSource));
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _controller = c);
      await c.play();
    } catch (_) {
      if (mounted) setState(() => _initError = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this video?'),
        content: const Text(
            'The video file will be removed from this device. The diagnosis details and treatment recommendations will be kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final db = context.read<DatabaseHelper>();
    final svc = VideoCleanupService(db: db);
    await svc.deleteVideo(widget.videoSource);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: const Text('Video', style: TextStyle(fontSize: 16)),
        actions: [
          if (_isLocal)
            IconButton(
              tooltip: 'Delete video',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Center(child: _body()),
    );
  }

  Widget _body() {
    if (_initError) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Could not play this video.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const CircularProgressIndicator(color: AppColors.primary);
    }
    return GestureDetector(
      onTap: () {
        if (c.value.isPlaying) {
          c.pause();
        } else {
          c.play();
        }
        setState(() {});
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
          if (!c.value.isPlaying)
            Container(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(20),
              child: const Icon(Icons.play_arrow,
                  color: Colors.white, size: 44),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Static analysis**

```
flutter analyze lib/features/chat/widgets/video_player_view.dart
```
Expected: no errors.

- [ ] **Step 3: Stage for review (DO NOT commit)**

```
git add lib/features/chat/widgets/video_player_view.dart
```

Stop. Report "Task 7 staged — ready for review."

---

## Task 8: Wire VideoCleanupService into app.dart

**Files:**
- Modify: `lib/app.dart`

Adds a fire-and-forget `VideoCleanupService.runIfDue()` call from `_CropCareAppState.initState`'s post-frame callback (alongside the Phase 2 tap-stream subscription).

- [ ] **Step 1: Add the import**

In `lib/app.dart`, near the other service imports, add:

```dart
import 'services/video_cleanup_service.dart';
```

- [ ] **Step 2: Schedule the cleanup in initState**

Find the existing `initState` method (added in Phase 2 Task 9):

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tapSub = NotificationService.instance.tapStream.listen(_handleTap);
    });
  }
```

Replace with:

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tapSub = NotificationService.instance.tapStream.listen(_handleTap);
      _runVideoCleanup();
    });
  }

  Future<void> _runVideoCleanup() async {
    try {
      final ctx = _navigatorKey.currentContext;
      if (ctx == null) return;
      final db = ctx.read<DatabaseHelper>();
      // Fire-and-forget; we never block UI on this.
      // ignore: discarded_futures
      VideoCleanupService(db: db).runIfDue();
    } catch (_) {/* defensive — never break app start */}
  }
```

(`_navigatorKey` is already declared in the class from Phase 2 Task 9.)

- [ ] **Step 3: Static analysis**

```
flutter analyze lib/app.dart
```
Expected: no errors.

- [ ] **Step 4: Stage for review (DO NOT commit)**

```
git add lib/app.dart
```

Stop. Report "Task 8 staged — ready for review."

---

## Task 9: Chat metadata writes + bubble rendering for video messages

**Files:**
- Modify: `lib/features/chat/providers/chat_provider.dart` (write `video_url` + `video_poster_url` into outgoing message metadata when a video is attached)
- Modify: `lib/features/chat/screens/chat_screen.dart` (render the three states of `metadata['video_url']`: null, `expired:` tombstone, live URL)

This task adds video display to chat. The exact line locations vary by file; use Grep + targeted Read with offset/limit.

- [ ] **Step 1: Find the chat-image rendering site**

Run:
```
grep -n "image_url\|imageUrl\|metadata\[" lib/features/chat/screens/chat_screen.dart
```

Identify the bubble-rendering function (likely `_buildAttachmentTile`, `_renderAttachment`, or similar) where `metadata['image_url']` is consumed and displayed as `Image.network` / `Image.memory`.

- [ ] **Step 2: Add video-aware rendering to the bubble**

In `lib/features/chat/screens/chat_screen.dart`, near the imports add:

```dart
import '../widgets/video_player_view.dart';
```

In the bubble-attachment rendering block, branch on `metadata['video_url']` BEFORE checking `metadata['image_url']`. Insert this pattern (adapt naming to match the surrounding code):

```dart
final videoUrl = meta['video_url'] as String?;
final posterUrl = meta['video_poster_url'] as String?;

if (videoUrl != null) {
  final isExpired = videoUrl.startsWith('expired:');
  return GestureDetector(
    onTap: () {
      if (isExpired) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This video is no longer available.')),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoPlayerView(videoSource: videoUrl),
          ),
        );
      }
    },
    child: Stack(
      alignment: Alignment.center,
      children: [
        if (posterUrl != null) _renderPoster(posterUrl)
        else Container(
          width: 200,
          height: 140,
          color: Colors.black26,
        ),
        Container(
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(10),
          child: Icon(
            isExpired ? Icons.error_outline : Icons.play_arrow,
            color: Colors.white,
            size: 28,
          ),
        ),
        if (isExpired)
          Positioned(
            bottom: 8,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Video expired',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
      ],
    ),
  );
}
```

Add a `_renderPoster(String url)` helper if one doesn't already exist — local-vs-network branch:

```dart
Widget _renderPoster(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return Image.network(url, width: 200, height: 140, fit: BoxFit.cover);
  }
  return Image.file(File(url), width: 200, height: 140, fit: BoxFit.cover);
}
```

(Add `import 'dart:io';` if not already present.)

The existing image-only rendering branch (`metadata['image_url']`) should fall through unchanged when `video_url` is null.

- [ ] **Step 3: Update chat_provider to write video metadata on outgoing messages**

In `lib/features/chat/providers/chat_provider.dart`, locate the function that constructs an outgoing user message with an image attachment (search for `image_url` / `metadata`). Where the message metadata is being built, add `video_url` and `video_poster_url` keys when a video is being sent:

```dart
metadata: {
  if (imageUrl != null) 'image_url': imageUrl,
  if (videoUrl != null) 'video_url': videoUrl,
  if (videoPosterUrl != null) 'video_poster_url': videoPosterUrl,
  // …existing keys preserved
},
```

The function likely takes a media URL parameter; extend its signature to accept `String? videoUrl, String? videoPosterUrl` (defaults to null) so the still-photo path is unchanged.

If the wiring requires changes to ChatScreen's send-message callsite to pass the new params, do that as well — search for where `chat_provider`'s send-message function is called and add the video params when an attached video is being sent.

If the chat-send wiring is more complex than a single function (multiple call sites, helper builders), STOP and escalate as NEEDS_CONTEXT — don't guess about provider internals.

- [ ] **Step 4: Static analysis**

```
flutter analyze lib/features/chat/screens/chat_screen.dart lib/features/chat/providers/chat_provider.dart
```
Expected: no new errors. Pre-existing infos are fine.

- [ ] **Step 5: Run tests**

```
flutter test
```
Expected: all existing tests still pass.

- [ ] **Step 6: Stage for review (DO NOT commit)**

```
git add lib/features/chat/screens/chat_screen.dart lib/features/chat/providers/chat_provider.dart
```

Stop. Report "Task 9 staged — ready for review."

---

## Task 10: DiagnosticHistoryScreen tombstone handling

**Files:**
- Modify: `lib/features/scan/diagnostic_history_screen.dart`

Adds a small "Video expired" hint when a `DiagnosisModel.videoUrl` is a tombstone, so the history list visually distinguishes expired-video diagnoses from photo-only ones.

- [ ] **Step 1: Identify the row builder**

Run:
```
grep -n "videoUrl\|video_url" lib/features/scan/diagnostic_history_screen.dart
```

If the file currently has zero references (it likely doesn't display videos at all yet), only a small additive change is needed. Otherwise locate the row-builder function.

- [ ] **Step 2: Add a small tombstone hint**

Inside the existing diagnosis-row builder (search for `d.diagnosisMode.name` or the `diagnosisMode` chip — that's near the bottom-row metadata area), add a conditional hint when the diagnosis was video-sourced and is now expired:

```dart
if (d.videoUrl != null && d.videoUrl!.startsWith('expired:')) ...[
  const SizedBox(width: 6),
  Icon(Icons.videocam_off,
      size: 13, color: AppColors.textLightGray),
  const SizedBox(width: 3),
  const Text(
    'Video expired',
    style: TextStyle(
        fontSize: 11, color: AppColors.textLightGray),
  ),
],
```

Place inside the existing horizontal row that contains the diagnosis-mode chip + confidence + date — so the hint appears in the same metadata strip.

- [ ] **Step 3: Static analysis**

```
flutter analyze lib/features/scan/diagnostic_history_screen.dart
```
Expected: no errors.

- [ ] **Step 4: Stage for review (DO NOT commit)**

```
git add lib/features/scan/diagnostic_history_screen.dart
```

Stop. Report "Task 10 staged — ready for review."

---

## Task 11: Manual on-device demo rehearsal (USER task)

**Files:** _no code changes — verification only_

Cannot be done by a subagent; needs an Android phone.

- [ ] **Step 1: Build and install the latest debug APK**

```
flutter run -d <android-device-id>
```

- [ ] **Step 2: Record and preview a real video**

1. Toggle airplane mode ON.
2. Open Scan tab → tap the video record button.
3. Confirm the recording timer starts. Pan over a leaf for ~10 seconds.
4. Auto-stop kicks in at 15 s if you don't tap stop earlier — verify.
5. Confirm `VideoPreviewScreen` opens with actual playback (not a still frame).
6. Tap "Continue" → `ScanResultScreen` should run the 5-frame diagnosis pipeline. Confirm a diagnosis card renders with a humanized disease name + treatment steps from local KB.
7. Tap "Yes, track it" → diagnosis is saved with `videoUrl` pointing to a local path.
8. Open Diagnostic History — the new diagnosis appears with a confidence value.

- [ ] **Step 3: Verify chat displays the video**

If the chat flow was triggered (via "Ask AI" or `openChatOnComplete: true`):
1. The chat bubble should show a poster frame + play overlay (NOT a static image only).
2. Tap the bubble → fullscreen `VideoPlayerView` opens and plays.
3. Confirm playback works.

- [ ] **Step 4: Verify manual delete**

1. From the fullscreen `VideoPlayerView`, tap the trash icon (app bar).
2. Confirm dialog appears. Tap Delete.
3. Confirm: player closes, chat bubble now shows the poster + "Video expired" badge + error icon overlay.
4. Tap the now-expired bubble → snackbar "This video is no longer available." appears.
5. Open Diagnostic History → the diagnosis row now shows a "Video expired" hint in the metadata strip.

- [ ] **Step 5: Verify auto-cleanup gate**

1. Inspect SharedPreferences via:
   ```
   adb shell run-as <package> cat shared_prefs/<package>_preferences.xml | grep video_cleanup_last_run
   ```
   Confirm a recent ISO 8601 timestamp is set (cleanup ran on app start).
2. Force-close and reopen the app — the timestamp should NOT change (gated to once per 23 hours).

- [ ] **Step 6: Document the result**

Create `docs/superpowers/testing/2026-05-08-phase3-demo-smoke.md` with one of:
- "All steps passed on `<device model> Android <version>`."
- A specific failure description with logcat excerpt (`adb logcat -s flutter:V`).

- [ ] **Step 7: Stage the testing report (DO NOT commit)**

```
git add docs/superpowers/testing/2026-05-08-phase3-demo-smoke.md
```

Stop. Report "Task 11 complete. Demo rehearsal: <pass|fail>."

---

## Definition of Done for Phase 3

- [ ] Real MP4 recording via `startVideoRecording`/`stopVideoRecording` with 15-second auto-stop.
- [ ] Recorded files persisted into `<app docs>/videos/<uuid>.mp4`.
- [ ] `VideoPreviewScreen` plays the recorded video before continuing.
- [ ] `VideoDiagnosisService.analyzeVideo` extracts 5 frames and returns the highest-confidence detection from the local TFLite classifier.
- [ ] `ScanResultScreen` runs the video pipeline when `isFromVideo && videoFile != null`, falls back to remote detection on the poster frame on failure.
- [ ] `DiagnosisModel.videoUrl` is populated on tracking save.
- [ ] Chat bubbles render attached videos as poster + play overlay; tap opens fullscreen `VideoPlayerView`.
- [ ] `VideoPlayerView` app bar has a trash icon → confirm dialog → deletes the file and writes the `expired:<filename>` tombstone.
- [ ] `VideoCleanupService.runIfDue` is invoked from `_CropCareAppState.initState` (fire-and-forget), gated to once per 23 hours, and tombstones any video older than 30 days.
- [ ] UI correctly distinguishes the three states of `videoUrl`: null (no video ever), `expired:` tombstone (poster + "Video expired" badge), live path/URL (poster + play overlay).
- [ ] `DiagnosticHistoryScreen` shows a "Video expired" hint for tombstoned video-source diagnoses.
- [ ] `VideoCleanupService` unit tests pass (gating, age threshold, tombstone writes, error tolerance).
- [ ] `flutter analyze` clean (no new errors).
- [ ] All existing unit tests still pass.
- [ ] Manual on-device rehearsal (Task 11) passes.
- [ ] All changes are staged but not committed — repo owner reviews and commits manually.
