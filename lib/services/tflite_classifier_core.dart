import 'dart:math' as math;
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
    validateModelContract(
      inputShape: inputShape,
      outputShape: outputTensor.shape,
      labelCount: labels.length,
    );
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
      scores =
          rawOutput.first.map((value) => (value - zeroPoint) * scale).toList();
    } else {
      final rawOutput = [List<double>.filled(labels.length, 0.0)];
      interpreter.run(input, rawOutput);
      scores = rawOutput.first;
    }
    if (scores.isEmpty) {
      throw Exception('The TFLite model returned no predictions.');
    }

    return responseForScores(
      scores: scores,
      labels: labels,
      cropType: cropType,
      source: source,
      modelName: modelName,
      modelVersion: modelVersion,
      filename: filename,
      modelSource: modelSource,
    );
  }

  /// Converts model scores into a diagnosis response.
  ///
  /// When [cropType] is provided, only that crop family's output classes are
  /// candidates for the primary diagnosis and confidence-margin validation.
  /// The global ranking is retained in diagnostic notes but cannot override
  /// an acceptable selected-family prediction. Raw TFLite outputs keep the
  /// existing logit conversion; [preserveProvidedScores] is for callers that
  /// supply already-interpreted unit-interval scores.
  AiBackendDetectResponse responseForScores({
    required List<double> scores,
    required List<String> labels,
    String? cropType,
    bool preserveProvidedScores = false,
    String source = 'local-tflite',
    String modelName = 'cropcare_efficientnet_v2',
    String modelVersion = 'v2-subset-100',
    String filename = 'image',
    String? modelSource,
  }) {
    if (scores.length != labels.length || scores.isEmpty) {
      throw StateError(
        'TFLite returned ${scores.length} scores for ${labels.length} labels.',
      );
    }
    final normalizedScores = preserveProvidedScores
        ? scores
            .map((value) => value.clamp(0.0, 1.0).toDouble())
            .toList(growable: false)
        : _normalizeFloatScores(scores);
    final requestedCropType = cropType?.trim().toLowerCase();
    final hasSelectedCrop =
        requestedCropType != null && requestedCropType.isNotEmpty;
    final globalRanking = rankCandidateIndices(
      scores: normalizedScores,
      labels: labels,
    );
    final detectionRanking = hasSelectedCrop
        ? rankCandidateIndices(
            scores: normalizedScores,
            labels: labels,
            cropType: requestedCropType,
          )
        : globalRanking;
    final topPredictions = globalRanking
        .take(3)
        .map((index) =>
            '${labels[index]} ${(normalizedScores[index] * 100).toStringAsFixed(1)}%')
        .join(' | ');

    if (detectionRanking.isEmpty) {
      return AiBackendDetectResponse(
        status: 'no_match',
        source: source,
        cropType: requestedCropType,
        detections: const [],
        model: AiBackendModelInfo(
          name: modelName,
          version: modelVersion,
        ),
        notes: [
          'The model has no output classes for the selected crop family: $requestedCropType.',
          'Input file: $filename',
          'Top predictions: $topPredictions',
          if (modelSource != null && modelSource.isNotEmpty)
            'Model source file: $modelSource',
        ],
      );
    }

    final primaryIndex = detectionRanking.first;
    final rawLabel = labels[primaryIndex];
    final score = normalizedScores[primaryIndex].clamp(0.0, 1.0).toDouble();
    final secondaryScore = detectionRanking.length > 1
        ? normalizedScores[detectionRanking[1]].clamp(0.0, 1.0).toDouble()
        : 0.0;
    final scoreMargin = (score - secondaryScore).clamp(-1.0, 1.0).toDouble();
    final labelSpec = _labelSpecFor(rawLabel);
    final predictedCropType = labelSpec.cropType?.value;
    final predictedCropFamily = labelSpec.cropFamily;
    final globalTopSpec = _labelSpecFor(labels[globalRanking.first]);
    final globalTopScore = normalizedScores[globalRanking.first];
    final globalMismatchNote = hasSelectedCrop &&
            globalTopSpec.cropFamily != requestedCropType
        ? 'Global highest prediction ${globalTopSpec.displayLabel} is outside the selected $requestedCropType family and was not used for diagnosis.'
        : null;
    final familyForCoverage =
        hasSelectedCrop ? requestedCropType : predictedCropFamily;
    final familyLabels = labels
        .where((label) => cropFamilyForLabel(label) == familyForCoverage)
        .toList(growable: false);
    final hasHealthyBaseline = familyLabels.any(_isHealthyLabel);
    final hasSufficientFamilyCoverage =
        familyLabels.length >= 2 && hasHealthyBaseline;
    final familyCoverageNote = hasSufficientFamilyCoverage
        ? null
        : 'The model has ${familyLabels.length} class${familyLabels.length == 1 ? '' : 'es'} for the ${familyForCoverage ?? 'predicted'} family${hasHealthyBaseline ? '' : ' and no healthy-leaf class'}; it cannot safely confirm a diagnosis for this family.';
    final possibleFamilyMismatch = hasSelectedCrop &&
        globalTopSpec.cropFamily != requestedCropType &&
        globalTopScore >= AppConstants.temporaryScannerAcceptedConfidence &&
        (score < AppConstants.temporaryScannerAcceptedConfidence ||
            globalTopScore - score >=
                AppConstants.temporaryScannerAcceptedMargin);
    final possibleFamilyMismatchNote = possibleFamilyMismatch
        ? 'Possible crop-family mismatch: the full-model top class ${globalTopSpec.displayLabel} scored ${(globalTopScore * 100).toStringAsFixed(1)}%, while the strongest $requestedCropType class scored ${(score * 100).toStringAsFixed(1)}%. The other-family class is not confirmed as a diagnosis.'
        : null;
    final sameCropConfidence = predictedCropType == null
        ? score
        : normalizedScores
            .asMap()
            .entries
            .where((entry) =>
                entry.key < labels.length &&
                cropFamilyForLabel(labels[entry.key]) == predictedCropType)
            .fold<double>(
              0.0,
              (sum, entry) => sum + entry.value.clamp(0.0, 1.0).toDouble(),
            )
            .clamp(0.0, 1.0)
            .toDouble();
    final isUnsupportedCropFamily = predictedCropType == null;
    final isSelectedCropMismatch =
        hasSelectedCrop && requestedCropType != predictedCropFamily;
    final isBelowAcceptedConfidence =
        score < AppConstants.temporaryScannerAcceptedConfidence;
    final isAmbiguous = detectionRanking.length > 1 &&
        scoreMargin < AppConstants.temporaryScannerAcceptedMargin;

    final topDetections = detectionRanking.take(3).map((index) {
      final candidateLabel = labels[index];
      final candidateSpec = _labelSpecFor(candidateLabel);
      return AiBackendDetectionItem(
        label: candidateSpec.displayLabel,
        labelKey: candidateSpec.labelKey,
        confidence: normalizedScores[index].clamp(0.0, 1.0).toDouble(),
        bbox: const AiBackendBoundingBox(
          x: 0,
          y: 0,
          width: 1,
          height: 1,
        ),
      );
    }).toList(growable: false);

    if (isUnsupportedCropFamily || isSelectedCropMismatch) {
      final rejectionNotes = <String>[
        isUnsupportedCropFamily
            ? 'The model predicted ${labelSpec.displayLabel}, which is outside CropCare AI\'s supported crops.'
            : 'The model predicted ${labelSpec.displayLabel}, but the selected crop is $requestedCropType.',
        'Input file: $filename',
        'Top predictions: $topPredictions',
        if (globalMismatchNote != null) globalMismatchNote,
        if (modelSource != null && modelSource.isNotEmpty)
          'Model source file: $modelSource',
      ];
      return AiBackendDetectResponse(
        status: 'no_match',
        source: source,
        cropType: requestedCropType ?? predictedCropType,
        detections: topDetections,
        model: AiBackendModelInfo(
          name: modelName,
          version: modelVersion,
        ),
        notes: rejectionNotes,
      );
    }

    if (isBelowAcceptedConfidence ||
        isAmbiguous ||
        !hasSufficientFamilyCoverage ||
        possibleFamilyMismatch) {
      final rejectionNotes = <String>[];
      if (isBelowAcceptedConfidence) {
        rejectionNotes.add(
          'Top prediction confidence was ${(score * 100).toStringAsFixed(1)}%, below the ${(AppConstants.temporaryScannerAcceptedConfidence * 100).toStringAsFixed(0)}% offline acceptance threshold.',
        );
      }
      if (isAmbiguous) {
        rejectionNotes.add(
          'Top prediction margin was ${(scoreMargin * 100).toStringAsFixed(1)}%, below the ${(AppConstants.temporaryScannerAcceptedMargin * 100).toStringAsFixed(0)}% confidence-gap threshold. The scan is too ambiguous to diagnose safely.',
        );
      }
      if (familyCoverageNote != null) {
        rejectionNotes.add(familyCoverageNote);
      }
      if (possibleFamilyMismatchNote != null) {
        rejectionNotes.add(possibleFamilyMismatchNote);
      }
      return AiBackendDetectResponse(
        status: 'no_match',
        source: source,
        cropType: requestedCropType ?? predictedCropType,
        detections: topDetections,
        model: AiBackendModelInfo(
          name: modelName,
          version: modelVersion,
        ),
        notes: [
          ...rejectionNotes,
          'Input file: $filename',
          'Top predictions: $topPredictions',
          if (globalMismatchNote != null) globalMismatchNote,
          if (modelSource != null && modelSource.isNotEmpty)
            'Model source file: $modelSource',
        ],
      );
    }

    final notes = <String>[
      'Temporary TFLite model result generated on device.',
      'Input file: $filename',
      'Top predictions: $topPredictions',
      if (globalMismatchNote != null) globalMismatchNote,
      hasSelectedCrop
          ? 'Selected-family prediction margin: ${(scoreMargin * 100).toStringAsFixed(1)}%'
          : 'Top prediction margin: ${(scoreMargin * 100).toStringAsFixed(1)}%',
      'Predicted crop-family confidence: ${(sameCropConfidence * 100).toStringAsFixed(1)}%',
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
      cropType: predictedCropType,
      detections: topDetections,
      model: AiBackendModelInfo(
        name: modelName,
        version: modelVersion,
      ),
      notes: notes,
    );
  }

  void validateModelContract({
    required List<int> inputShape,
    required List<int> outputShape,
    required int labelCount,
  }) {
    if (inputShape.length != 4 ||
        inputShape.first != 1 ||
        inputShape[1] <= 0 ||
        inputShape[2] <= 0 ||
        inputShape[3] != 3) {
      throw StateError(
        'Unsupported TFLite input shape $inputShape; expected [1, height, width, 3].',
      );
    }
    if (labelCount <= 0) {
      throw StateError('The TFLite label file is empty.');
    }
    if (outputShape.length != 2 ||
        outputShape.first != 1 ||
        outputShape.last != labelCount) {
      throw StateError(
        'TFLite model output shape $outputShape does not match $labelCount labels.',
      );
    }
  }

  List<int> rankCandidateIndices({
    required List<double> scores,
    required List<String> labels,
    String? cropType,
  }) {
    final allIndices = List.generate(scores.length, (index) => index);
    final requestedCrop = cropType?.trim().toLowerCase();
    final candidates = requestedCrop == null || requestedCrop.isEmpty
        ? allIndices
        : allIndices.where((index) {
            if (index >= labels.length) return false;
            return cropFamilyForLabel(labels[index]) == requestedCrop;
          }).toList(growable: false);
    final ranked = [...candidates];
    ranked.sort((a, b) => scores[b].compareTo(scores[a]));
    return ranked;
  }

  /// Returns the crop family encoded in an output label, including legacy
  /// labels for families that are not selectable in the app.
  String? cropFamilyForLabel(String rawLabel) =>
      _labelSpecFor(rawLabel).cropFamily;

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

    final resizedRgb = _resizeWithTrainingBilinear(
      img.bakeOrientation(decoded),
      width: inputWidth,
      height: inputHeight,
    );

    if (inputDtype == TfliteInputDtype.uint8) {
      return Uint8List.fromList(
        resizedRgb.map((value) => value.round().clamp(0, 255).toInt()).toList(),
      );
    }

    return [
      List.generate(
        inputHeight,
        (y) => List.generate(
          inputWidth,
          (x) => [
            resizedRgb[(y * inputWidth + x) * 3],
            resizedRgb[(y * inputWidth + x) * 3 + 1],
            resizedRgb[(y * inputWidth + x) * 3 + 2],
          ],
        ),
      ),
    ];
  }

  List<double> _normalizeFloatScores(List<double> rawScores) {
    if (rawScores.isEmpty) {
      return rawScores;
    }

    final allFinite = rawScores.every((value) => value.isFinite);
    if (!allFinite) {
      return List<double>.filled(rawScores.length, 0.0);
    }

    if (_looksLikeProbabilityDistribution(rawScores)) {
      return rawScores
          .map((value) => value.clamp(0.0, 1.0).toDouble())
          .toList();
    }

    final maxScore = rawScores.reduce((a, b) => a > b ? a : b);
    final exponentials = rawScores
        .map((value) => math.exp(value - maxScore))
        .toList(growable: false);
    final total = exponentials.fold<double>(0.0, (sum, value) => sum + value);
    if (!total.isFinite || total <= 0) {
      return rawScores
          .map((value) => value.clamp(0.0, 1.0).toDouble())
          .toList();
    }

    return exponentials.map((value) => value / total).toList(growable: false);
  }

  bool _looksLikeProbabilityDistribution(List<double> values) {
    final allInRange = values.every((value) => value >= 0 && value <= 1);
    if (!allInRange) {
      return false;
    }

    final total = values.fold<double>(0.0, (sum, value) => sum + value);
    return total >= 0.95 && total <= 1.05;
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

  bool _isHealthyLabel(String rawLabel) =>
      _normalizeLabelKey(rawLabel).split('_').contains('healthy');
}

/// Mirrors TensorFlow's default bilinear resize used by
/// `image_dataset_from_directory`: pixel-center sampling, edge clamping, and
/// no antialias filter while downsampling. Keep values fractional to match the
/// float32 image tensors used for training.
Float32List _resizeWithTrainingBilinear(
  img.Image source, {
  required int width,
  required int height,
}) {
  final resized = Float32List(width * height * 3);
  final scaleX = source.width / width;
  final scaleY = source.height / height;
  for (var y = 0; y < height; y++) {
    final sourceY =
        ((y + 0.5) * scaleY - 0.5).clamp(0.0, (source.height - 1).toDouble());
    final topY = sourceY.floor();
    final bottomY = math.min(topY + 1, source.height - 1);
    final weightY = sourceY - topY;
    for (var x = 0; x < width; x++) {
      final sourceX =
          ((x + 0.5) * scaleX - 0.5).clamp(0.0, (source.width - 1).toDouble());
      final leftX = sourceX.floor();
      final rightX = math.min(leftX + 1, source.width - 1);
      final weightX = sourceX - leftX;
      final topLeft = source.getPixel(leftX, topY);
      final topRight = source.getPixel(rightX, topY);
      final bottomLeft = source.getPixel(leftX, bottomY);
      final bottomRight = source.getPixel(rightX, bottomY);
      final offset = (y * width + x) * 3;
      for (var channel = 0; channel < 3; channel++) {
        final top = topLeft[channel].toDouble() * (1 - weightX) +
            topRight[channel].toDouble() * weightX;
        final bottom = bottomLeft[channel].toDouble() * (1 - weightX) +
            bottomRight[channel].toDouble() * weightX;
        resized[offset + channel] = top * (1 - weightY) + bottom * weightY;
      }
    }
  }
  return resized;
}

class _LabelSpec {
  final String rawLabel;
  final String displayLabel;
  final String labelKey;
  final CropType? cropType;
  final String? cropFamilyOverride;
  final bool supportedInKnowledgeBase;

  String? get cropFamily => cropFamilyOverride ?? cropType?.value;

  const _LabelSpec({
    required this.rawLabel,
    required this.displayLabel,
    required this.labelKey,
    this.cropType,
    this.cropFamilyOverride,
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
  'squash_healthy': _LabelSpec(
    rawLabel: 'squash_healthy',
    displayLabel: 'Squash Healthy',
    labelKey: 'squash_healthy',
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
    cropFamilyOverride: 'corn',
  ),
  'Corn_(maize)___Common_rust_': _LabelSpec(
    rawLabel: 'Corn_(maize)___Common_rust_',
    displayLabel: 'Corn Common Rust',
    labelKey: 'corn_common_rust',
    cropFamilyOverride: 'corn',
  ),
  'Corn_(maize)___Northern_Leaf_Blight': _LabelSpec(
    rawLabel: 'Corn_(maize)___Northern_Leaf_Blight',
    displayLabel: 'Corn Northern Leaf Blight',
    labelKey: 'corn_northern_leaf_blight',
    cropFamilyOverride: 'corn',
  ),
  'Corn_(maize)___healthy': _LabelSpec(
    rawLabel: 'Corn_(maize)___healthy',
    displayLabel: 'Corn Healthy',
    labelKey: 'corn_healthy',
    cropFamilyOverride: 'corn',
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
    supportedInKnowledgeBase: true,
  ),
  'Eggplant_white_mold': _LabelSpec(
    rawLabel: 'Eggplant_white_mold',
    displayLabel: 'Eggplant White Mold',
    labelKey: 'eggplant_white_mold',
    cropType: CropType.eggplant,
    supportedInKnowledgeBase: true,
  ),
  'Eggplant_wilt': _LabelSpec(
    rawLabel: 'Eggplant_wilt',
    displayLabel: 'Eggplant Wilt',
    labelKey: 'eggplant_wilt',
    cropType: CropType.eggplant,
    supportedInKnowledgeBase: true,
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
