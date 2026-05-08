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
