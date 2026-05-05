import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/constants/app_constants.dart';
import '../data/models/ai_backend_models.dart';
import 'tflite_classifier_core.dart';

/// Loads two TFLite models and dispatches to the right one based on the
/// caller's [cropType] hint:
///
/// - **Eggplant** scans → [AppConstants.eggplantScannerModelAsset]
///   (legacy 16-class model — keeps eggplant detection alive while v2 lacks
///   eggplant training data).
/// - **All other crops** → [AppConstants.temporaryScannerModelAsset]
///   (cropcare_v2_subset_100, 13 classes covering tomato, pepper, squash;
///   significantly higher accuracy than the legacy model on those crops).
///
/// Both interpreters are loaded lazily on first use. If the eggplant
/// interpreter fails to load (asset missing, etc.) we fall back to the
/// primary v2 interpreter for everything; the call will surface a low
/// confidence note rather than crash.
class LocalClassifierService {
  Interpreter? _primaryInterpreter;
  List<String>? _primaryLabels;

  Interpreter? _eggplantInterpreter;
  List<String>? _eggplantLabels;

  final TfliteClassifierCore _core = const TfliteClassifierCore();

  Future<AiBackendDetectResponse> classifyImage({
    required List<int> imageBytes,
    required String filename,
    String? cropType,
  }) async {
    await _ensurePrimaryLoaded();

    final useEggplantModel = (cropType?.toLowerCase() == 'eggplant');
    final eggplantReady = useEggplantModel ? await _ensureEggplantLoaded() : false;

    final Interpreter interpreter;
    final List<String> labels;
    final String modelName;
    final String modelVersion;
    final String modelAssetPath;

    if (useEggplantModel && eggplantReady) {
      interpreter = _eggplantInterpreter!;
      labels = _eggplantLabels!;
      modelName = 'cropcare_efficientnet_with_eggplant';
      modelVersion = 'legacy-base';
      modelAssetPath = AppConstants.eggplantScannerModelAsset;
    } else {
      interpreter = _primaryInterpreter!;
      labels = _primaryLabels!;
      modelName = 'cropcare_efficientnet_v2';
      modelVersion = 'v2-subset-100';
      modelAssetPath = AppConstants.temporaryScannerModelAsset;
    }

    return _core.classifyImage(
      imageBytes: Uint8List.fromList(imageBytes),
      filename: filename,
      interpreter: interpreter,
      labels: labels,
      cropType: cropType,
      source: 'local-tflite',
      modelName: modelName,
      modelVersion: modelVersion,
      modelSource: modelAssetPath.split('/').last,
    );
  }

  Future<void> _ensurePrimaryLoaded() async {
    if (_primaryInterpreter != null && _primaryLabels != null) {
      return;
    }

    _primaryInterpreter = await Interpreter.fromAsset(
      AppConstants.temporaryScannerModelAsset,
    );

    final rawLabels = await rootBundle.loadString(
      AppConstants.temporaryScannerLabelsAsset,
    );
    _primaryLabels = _parseLabels(rawLabels);
  }

  Future<bool> _ensureEggplantLoaded() async {
    if (_eggplantInterpreter != null && _eggplantLabels != null) {
      return true;
    }
    try {
      _eggplantInterpreter = await Interpreter.fromAsset(
        AppConstants.eggplantScannerModelAsset,
      );
      final rawLabels = await rootBundle.loadString(
        AppConstants.eggplantScannerLabelsAsset,
      );
      _eggplantLabels = _parseLabels(rawLabels);
      return true;
    } catch (_) {
      _eggplantInterpreter = null;
      _eggplantLabels = null;
      return false;
    }
  }

  List<String> _parseLabels(String raw) {
    return raw
        .split('\n')
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList();
  }
}
