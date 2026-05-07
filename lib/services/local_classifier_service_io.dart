import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/constants/app_constants.dart';
import '../data/models/ai_backend_models.dart';
import 'tflite_classifier_core.dart';

/// Loads the shipped on-device TFLite model.
///
/// The current runtime model only supports tomato, pepper, and squash labels.
/// If a caller explicitly asks to scan an unsupported crop such as eggplant or
/// pechay, the service returns a `no_match` response so the UI can reject the
/// scan cleanly instead of forcing it through the wrong label set.
class LocalClassifierService {
  static const String _modelName = 'cropcare_efficientnet_v2';
  static const String _modelVersion = 'v2-subset-100';

  Interpreter? _interpreter;
  List<String>? _labels;
  Set<String>? _supportedCropTypes;

  final TfliteClassifierCore _core = const TfliteClassifierCore();

  Future<AiBackendDetectResponse> classifyImage({
    required List<int> imageBytes,
    required String filename,
    String? cropType,
  }) async {
    await _ensureLoaded();

    final normalizedCropType = cropType?.trim().toLowerCase();
    final supportedCropTypes = _supportedCropTypes ?? const <String>{};
    if (normalizedCropType != null &&
        normalizedCropType.isNotEmpty &&
        !supportedCropTypes.contains(normalizedCropType)) {
      final supportedCropList = supportedCropTypes.toList()..sort();
      return AiBackendDetectResponse(
        status: 'no_match',
        source: 'local-tflite',
        cropType: normalizedCropType,
        detections: const [],
        model: const AiBackendModelInfo(
          name: _modelName,
          version: _modelVersion,
        ),
        notes: [
          'The current on-device model supports ${supportedCropList.join(', ')} scans only.',
          'Selected crop: $normalizedCropType',
          'Model source file: ${AppConstants.temporaryScannerModelAsset.split('/').last}',
        ],
      );
    }

    return _core.classifyImage(
      imageBytes: Uint8List.fromList(imageBytes),
      filename: filename,
      interpreter: _interpreter!,
      labels: _labels!,
      cropType: normalizedCropType,
      source: 'local-tflite',
      modelName: _modelName,
      modelVersion: _modelVersion,
      modelSource: AppConstants.temporaryScannerModelAsset.split('/').last,
    );
  }

  Future<void> _ensureLoaded() async {
    if (_interpreter != null && _labels != null) {
      return;
    }

    _interpreter = await Interpreter.fromAsset(
      AppConstants.temporaryScannerModelAsset,
    );

    final rawLabels = await rootBundle.loadString(
      AppConstants.temporaryScannerLabelsAsset,
    );
    _labels = _parseLabels(rawLabels);
    _supportedCropTypes = _extractCropTypes(_labels!);
  }

  List<String> _parseLabels(String raw) {
    return raw
        .split('\n')
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList();
  }

  Set<String> _extractCropTypes(List<String> labels) {
    return labels
        .map((label) => label.trim().toLowerCase())
        .map((label) {
          final separatorIndex = label.indexOf('_');
          if (separatorIndex == -1) {
            return label;
          }
          return label.substring(0, separatorIndex);
        })
        .where((cropType) => cropType.isNotEmpty)
        .toSet();
  }
}
