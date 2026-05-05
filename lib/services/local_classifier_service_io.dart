import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/constants/app_constants.dart';
import '../data/models/ai_backend_models.dart';
import 'tflite_classifier_core.dart';

class LocalClassifierService {
  Interpreter? _interpreter;
  List<String>? _labels;
  final TfliteClassifierCore _core = const TfliteClassifierCore();

  Future<AiBackendDetectResponse> classifyImage({
    required List<int> imageBytes,
    required String filename,
    String? cropType,
  }) async {
    await _ensureLoaded();

    return _core.classifyImage(
      imageBytes: Uint8List.fromList(imageBytes),
      filename: filename,
      interpreter: _interpreter!,
      labels: _labels!,
      cropType: cropType,
      source: 'local-tflite',
      modelName: 'cropcare_efficientnet_with_eggplant',
      modelVersion: 'temporary-v1',
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
    _labels = rawLabels
        .split('\n')
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList();
  }
}
