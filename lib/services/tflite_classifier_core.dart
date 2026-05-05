import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/app_enums.dart';
import '../data/models/ai_backend_models.dart';

/// Tensor input dtype that the underlying TFLite model expects.
///
/// EfficientNet float32 models receive ``[1, H, W, 3]`` doubles in
/// ``[0, 255]`` (preprocessing happens inside the model graph). INT8
/// post-quantized models receive a flat ``Uint8List`` of raw RGB bytes.
enum TfliteInputDtype { float32, uint8 }

class TfliteClassifierCore {
  const TfliteClassifierCore();

  AiBackendDetectResponse classifyImage({
    required Uint8List imageBytes,
    required String filename,
    required Interpreter interpreter,
    required List<String> labels,
    String? cropType,
    String source = 'local-tflite',
    String modelName = 'cropcare_efficientnet_v2',
    String modelVersion = 'v2-subset-100',
    String? modelSource,
  }) {
    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    final inputShape = inputTensor.shape;
    final inputHeight = inputShape[1];
    final inputWidth = inputShape[2];
    final isUint8Input =
        inputTensor.type.toString().toLowerCase().contains('uint8');
    final isUint8Output =
        outputTensor.type.toString().toLowerCase().contains('uint8');

    final input = buildEfficientNetInputTensor(
      imageBytes: imageBytes,
      inputHeight: inputHeight,
      inputWidth: inputWidth,
      inputDtype:
          isUint8Input ? TfliteInputDtype.uint8 : TfliteInputDtype.float32,
    );

    final List<double> scores;
    if (isUint8Output) {
      final rawOutput = [List<int>.filled(labels.length, 0)];
      interpreter.run(input, rawOutput);
      final params = outputTensor.params;
      final scale = params.scale;
      final zeroPoint = params.zeroPoint;
      scores = rawOutput.first
          .map((value) => (value - zeroPoint) * scale)
          .toList();
      final total = scores.fold<double>(0.0, (a, b) => a + b);
      if (total > 0) {
        for (var i = 0; i < scores.length; i++) {
          scores[i] = scores[i] / total;
        }
      }
    } else {
      final rawOutput = [List<double>.filled(labels.length, 0.0)];
      interpreter.run(input, rawOutput);
      scores = rawOutput.first;
    }
    if (scores.isEmpty) {
      throw Exception('The TFLite model returned no predictions.');
    }

    final ranked = List.generate(scores.length, (index) => index)
      ..sort((a, b) => scores[b].compareTo(scores[a]));

    final primaryIndex = ranked.first;
    final rawLabel = labels[primaryIndex];
    final score = scores[primaryIndex].clamp(0.0, 1.0).toDouble();
    final secondaryScore = ranked.length > 1
        ? scores[ranked[1]].clamp(0.0, 1.0).toDouble()
        : 0.0;
    final scoreMargin = (score - secondaryScore).clamp(-1.0, 1.0).toDouble();
    final labelSpec = _labelSpecFor(rawLabel);
    final isLowConfidence =
        score < AppConstants.temporaryScannerAcceptedConfidence;

    final topPredictions = ranked
        .take(3)
        .map((index) =>
            '${labels[index]} ${(scores[index] * 100).toStringAsFixed(1)}%')
        .join(' | ');

    if (isLowConfidence) {
      return AiBackendDetectResponse(
        status: 'no_match',
        source: source,
        cropType: cropType,
        detections: const [],
        model: AiBackendModelInfo(
          name: modelName,
          version: modelVersion,
        ),
        notes: [
          'Top prediction confidence was ${(score * 100).toStringAsFixed(1)}%, below the ${(AppConstants.temporaryScannerAcceptedConfidence * 100).toStringAsFixed(0)}% acceptance threshold.',
          'Input file: $filename',
          'Top predictions: $topPredictions',
          if (modelSource != null && modelSource.isNotEmpty)
            'Model source file: $modelSource',
        ],
      );
    }

    final notes = <String>[
      'Temporary TFLite model result generated on the backend.',
      'Input file: $filename',
      'Top predictions: $topPredictions',
      if (!labelSpec.supportedInKnowledgeBase)
        'This predicted class is not fully covered by the current app knowledge base yet.',
      if (score < AppConstants.temporaryScannerMinConfidence)
        'Confidence is low. Try another clear leaf photo before trusting the result.',
      if (modelSource != null && modelSource.isNotEmpty)
        'Model source file: $modelSource',
    ];

    return AiBackendDetectResponse(
      status: 'ok',
      source: source,
      cropType: labelSpec.cropType?.value ?? cropType,
      detections: [
        AiBackendDetectionItem(
          label: labelSpec.displayLabel,
          labelKey: labelSpec.labelKey,
          confidence: score,
          bbox: const AiBackendBoundingBox(
            x: 0,
            y: 0,
            width: 1,
            height: 1,
          ),
        ),
      ],
      model: AiBackendModelInfo(
        name: modelName,
        version: modelVersion,
      ),
      notes: notes,
    );
  }

  /// Build the per-image input tensor for EfficientNetB0.
  ///
  /// Returns a `List<List<List<List<double>>>>` shaped
  /// `[1, H, W, 3]` for float32 models, or a flat `Uint8List` of raw
  /// RGB bytes for INT8 quantized models. Both contain raw `[0, 255]`
  /// values — EfficientNet's preprocessing layer (or the quantization
  /// scale/zero-point) handles normalization.
  Object buildEfficientNetInputTensor({
    required List<int> imageBytes,
    required int inputHeight,
    required int inputWidth,
    TfliteInputDtype inputDtype = TfliteInputDtype.float32,
  }) {
    final decoded = img.decodeImage(Uint8List.fromList(imageBytes));
    if (decoded == null) {
      throw Exception('Failed to decode image for TFLite inference.');
    }

    final resized = img.copyResize(
      decoded,
      width: inputWidth,
      height: inputHeight,
      interpolation: img.Interpolation.average,
    );

    if (inputDtype == TfliteInputDtype.uint8) {
      final buffer = Uint8List(inputHeight * inputWidth * 3);
      var offset = 0;
      for (var y = 0; y < inputHeight; y++) {
        for (var x = 0; x < inputWidth; x++) {
          final pixel = resized.getPixel(x, y);
          buffer[offset++] = pixel.r.toInt();
          buffer[offset++] = pixel.g.toInt();
          buffer[offset++] = pixel.b.toInt();
        }
      }
      return buffer;
    }

    return [
      List.generate(
        inputHeight,
        (y) => List.generate(
          inputWidth,
          (x) {
            final pixel = resized.getPixel(x, y);
            return [
              pixel.r.toDouble(),
              pixel.g.toDouble(),
              pixel.b.toDouble(),
            ];
          },
        ),
      ),
    ];
  }

  _LabelSpec _labelSpecFor(String rawLabel) {
    return _labelSpecs[rawLabel] ??
        _LabelSpec(
          rawLabel: rawLabel,
          displayLabel: _humanize(rawLabel),
          labelKey: _normalizeLabelKey(rawLabel),
        );
  }

  String _humanize(String value) {
    return value
        .replaceAll('___', ' ')
        .replaceAll('_', ' ')
        .replaceAll(',', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .split(' ')
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _normalizeLabelKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}

class _LabelSpec {
  final String rawLabel;
  final String displayLabel;
  final String labelKey;
  final CropType? cropType;
  final bool supportedInKnowledgeBase;

  const _LabelSpec({
    required this.rawLabel,
    required this.displayLabel,
    required this.labelKey,
    this.cropType,
    this.supportedInKnowledgeBase = false,
  });
}

const Map<String, _LabelSpec> _labelSpecs = {
  'pepper_bacterial_spot': _LabelSpec(
    rawLabel: 'pepper_bacterial_spot',
    displayLabel: 'Bell Pepper Bacterial Spot',
    labelKey: 'pepper_bacterial_spot',
    cropType: CropType.pepper,
    supportedInKnowledgeBase: true,
  ),
  'pepper_healthy': _LabelSpec(
    rawLabel: 'pepper_healthy',
    displayLabel: 'Bell Pepper Healthy',
    labelKey: 'pepper_healthy',
    cropType: CropType.pepper,
    supportedInKnowledgeBase: true,
  ),
  'squash_powdery_mildew': _LabelSpec(
    rawLabel: 'squash_powdery_mildew',
    displayLabel: 'Squash Powdery Mildew',
    labelKey: 'squash_powdery_mildew',
    cropType: CropType.squash,
  ),
  'tomato_bacterial_spot': _LabelSpec(
    rawLabel: 'tomato_bacterial_spot',
    displayLabel: 'Tomato Bacterial Spot',
    labelKey: 'tomato_bacterial_spot',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'tomato_early_blight': _LabelSpec(
    rawLabel: 'tomato_early_blight',
    displayLabel: 'Tomato Early Blight',
    labelKey: 'tomato_early_blight',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'tomato_late_blight': _LabelSpec(
    rawLabel: 'tomato_late_blight',
    displayLabel: 'Tomato Late Blight',
    labelKey: 'tomato_late_blight',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'tomato_leaf_mold': _LabelSpec(
    rawLabel: 'tomato_leaf_mold',
    displayLabel: 'Tomato Leaf Mold',
    labelKey: 'tomato_leaf_mold',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'tomato_mosaic_virus': _LabelSpec(
    rawLabel: 'tomato_mosaic_virus',
    displayLabel: 'Tomato Mosaic Virus',
    labelKey: 'tomato_mosaic_virus',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'tomato_septoria_leaf_spot': _LabelSpec(
    rawLabel: 'tomato_septoria_leaf_spot',
    displayLabel: 'Tomato Septoria Leaf Spot',
    labelKey: 'tomato_septoria_leaf_spot',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'tomato_spider_mites': _LabelSpec(
    rawLabel: 'tomato_spider_mites',
    displayLabel: 'Tomato Spider Mites',
    labelKey: 'tomato_spider_mites',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'tomato_target_spot': _LabelSpec(
    rawLabel: 'tomato_target_spot',
    displayLabel: 'Tomato Target Spot',
    labelKey: 'tomato_target_spot',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'tomato_yellow_leaf_curl_virus': _LabelSpec(
    rawLabel: 'tomato_yellow_leaf_curl_virus',
    displayLabel: 'Tomato Yellow Leaf Curl Virus',
    labelKey: 'tomato_yellow_leaf_curl_virus',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'tomato_healthy': _LabelSpec(
    rawLabel: 'tomato_healthy',
    displayLabel: 'Tomato Healthy',
    labelKey: 'tomato_healthy',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'Corn_(maize)___Cercospora_leaf_spot Gray_leaf_spot': _LabelSpec(
    rawLabel: 'Corn_(maize)___Cercospora_leaf_spot Gray_leaf_spot',
    displayLabel: 'Corn Cercospora Leaf Spot / Gray Leaf Spot',
    labelKey: 'corn_cercospora_leaf_spot_gray_leaf_spot',
  ),
  'Corn_(maize)___Common_rust_': _LabelSpec(
    rawLabel: 'Corn_(maize)___Common_rust_',
    displayLabel: 'Corn Common Rust',
    labelKey: 'corn_common_rust',
  ),
  'Corn_(maize)___Northern_Leaf_Blight': _LabelSpec(
    rawLabel: 'Corn_(maize)___Northern_Leaf_Blight',
    displayLabel: 'Corn Northern Leaf Blight',
    labelKey: 'corn_northern_leaf_blight',
  ),
  'Corn_(maize)___healthy': _LabelSpec(
    rawLabel: 'Corn_(maize)___healthy',
    displayLabel: 'Corn Healthy',
    labelKey: 'corn_healthy',
  ),
  'Eggplant_healthy': _LabelSpec(
    rawLabel: 'Eggplant_healthy',
    displayLabel: 'Eggplant Healthy',
    labelKey: 'eggplant_healthy',
    cropType: CropType.eggplant,
    supportedInKnowledgeBase: true,
  ),
  'Eggplant_insect_pest': _LabelSpec(
    rawLabel: 'Eggplant_insect_pest',
    displayLabel: 'Eggplant Insect Pest',
    labelKey: 'eggplant_insect_pest',
    cropType: CropType.eggplant,
    supportedInKnowledgeBase: true,
  ),
  'Eggplant_leaf_spot': _LabelSpec(
    rawLabel: 'Eggplant_leaf_spot',
    displayLabel: 'Eggplant Leaf Spot',
    labelKey: 'eggplant_leaf_spot',
    cropType: CropType.eggplant,
    supportedInKnowledgeBase: true,
  ),
  'Eggplant_mosaic_virus': _LabelSpec(
    rawLabel: 'Eggplant_mosaic_virus',
    displayLabel: 'Eggplant Mosaic Virus',
    labelKey: 'eggplant_mosaic_virus',
    cropType: CropType.eggplant,
    supportedInKnowledgeBase: true,
  ),
  'Eggplant_small_leaf': _LabelSpec(
    rawLabel: 'Eggplant_small_leaf',
    displayLabel: 'Eggplant Small Leaf',
    labelKey: 'eggplant_small_leaf',
    cropType: CropType.eggplant,
  ),
  'Eggplant_white_mold': _LabelSpec(
    rawLabel: 'Eggplant_white_mold',
    displayLabel: 'Eggplant White Mold',
    labelKey: 'eggplant_white_mold',
    cropType: CropType.eggplant,
  ),
  'Eggplant_wilt': _LabelSpec(
    rawLabel: 'Eggplant_wilt',
    displayLabel: 'Eggplant Wilt',
    labelKey: 'eggplant_wilt',
    cropType: CropType.eggplant,
  ),
  'Pepper,_bell___Bacterial_spot': _LabelSpec(
    rawLabel: 'Pepper,_bell___Bacterial_spot',
    displayLabel: 'Bell Pepper Bacterial Spot',
    labelKey: 'pepper_bacterial_spot',
    cropType: CropType.pepper,
    supportedInKnowledgeBase: true,
  ),
  'Pepper,_bell___healthy': _LabelSpec(
    rawLabel: 'Pepper,_bell___healthy',
    displayLabel: 'Bell Pepper Healthy',
    labelKey: 'pepper_healthy',
    cropType: CropType.pepper,
    supportedInKnowledgeBase: true,
  ),
  'Squash___Powdery_mildew': _LabelSpec(
    rawLabel: 'Squash___Powdery_mildew',
    displayLabel: 'Squash Powdery Mildew',
    labelKey: 'squash_powdery_mildew',
    cropType: CropType.squash,
  ),
  'Tomato___Bacterial_spot': _LabelSpec(
    rawLabel: 'Tomato___Bacterial_spot',
    displayLabel: 'Tomato Bacterial Spot',
    labelKey: 'tomato_bacterial_spot',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'Tomato___Early_blight': _LabelSpec(
    rawLabel: 'Tomato___Early_blight',
    displayLabel: 'Tomato Early Blight',
    labelKey: 'tomato_early_blight',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'Tomato___Late_blight': _LabelSpec(
    rawLabel: 'Tomato___Late_blight',
    displayLabel: 'Tomato Late Blight',
    labelKey: 'tomato_late_blight',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'Tomato___Leaf_Mold': _LabelSpec(
    rawLabel: 'Tomato___Leaf_Mold',
    displayLabel: 'Tomato Leaf Mold',
    labelKey: 'tomato_leaf_mold',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'Tomato___Septoria_leaf_spot': _LabelSpec(
    rawLabel: 'Tomato___Septoria_leaf_spot',
    displayLabel: 'Tomato Septoria Leaf Spot',
    labelKey: 'tomato_septoria_leaf_spot',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'Tomato___Spider_mites Two-spotted_spider_mite': _LabelSpec(
    rawLabel: 'Tomato___Spider_mites Two-spotted_spider_mite',
    displayLabel: 'Tomato Spider Mites',
    labelKey: 'tomato_spider_mites',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'Tomato___Target_Spot': _LabelSpec(
    rawLabel: 'Tomato___Target_Spot',
    displayLabel: 'Tomato Target Spot',
    labelKey: 'tomato_target_spot',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'Tomato___Tomato_Yellow_Leaf_Curl_Virus': _LabelSpec(
    rawLabel: 'Tomato___Tomato_Yellow_Leaf_Curl_Virus',
    displayLabel: 'Tomato Yellow Leaf Curl Virus',
    labelKey: 'tomato_yellow_leaf_curl_virus',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'Tomato___Tomato_mosaic_virus': _LabelSpec(
    rawLabel: 'Tomato___Tomato_mosaic_virus',
    displayLabel: 'Tomato Mosaic Virus',
    labelKey: 'tomato_mosaic_virus',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
  'Tomato___healthy': _LabelSpec(
    rawLabel: 'Tomato___healthy',
    displayLabel: 'Tomato Healthy',
    labelKey: 'tomato_healthy',
    cropType: CropType.tomato,
    supportedInKnowledgeBase: true,
  ),
};
