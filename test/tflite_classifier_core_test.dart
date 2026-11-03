import 'package:cropcare_ai/core/constants/app_constants.dart';
import 'package:cropcare_ai/services/tflite_classifier_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

const _validatePackagedAssets = bool.fromEnvironment('TFLITE_VALIDATE_ASSETS');
late List<String> _packagedLabels;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    _packagedLabels = (await rootBundle.loadString(
      AppConstants.temporaryScannerLabelsAsset,
    ))
        .split('\n')
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList(growable: false);
  });

  test('Float32 input branch keeps raw RGB channel values', () {
    final image = img.Image(width: 1, height: 1)
      ..setPixelRgb(0, 0, 255, 128, 0);
    final bytes = img.encodePng(image);

    final input = const TfliteClassifierCore().buildEfficientNetInputTensor(
      imageBytes: bytes,
      inputHeight: 1,
      inputWidth: 1,
      inputDtype: TfliteInputDtype.float32,
    );

    expect(input, isA<List<List<List<List<double>>>>>());
    final floatInput = input as List<List<List<List<double>>>>;
    expect(floatInput[0][0][0], [255.0, 128.0, 0.0]);
  });

  test('Uint8 input branch packs raw RGB into a Uint8List', () {
    final image = img.Image(width: 1, height: 1)
      ..setPixelRgb(0, 0, 255, 128, 0);
    final bytes = img.encodePng(image);

    final input = const TfliteClassifierCore().buildEfficientNetInputTensor(
      imageBytes: bytes,
      inputHeight: 1,
      inputWidth: 1,
      inputDtype: TfliteInputDtype.uint8,
    );

    expect(input, isA<Uint8List>());
    expect((input as Uint8List).toList(), [255, 128, 0]);
  });

  test('image resize uses the bilinear interpolation used by training', () {
    final image = img.Image(width: 2, height: 1)
      ..setPixelRgb(0, 0, 255, 0, 0)
      ..setPixelRgb(1, 0, 0, 0, 255);
    final bytes = img.encodePng(image);

    final input = const TfliteClassifierCore().buildEfficientNetInputTensor(
      imageBytes: bytes,
      inputHeight: 1,
      inputWidth: 3,
    ) as List<List<List<List<double>>>>;

    expect(input[0][0][0], [255.0, 0.0, 0.0]);
    expect(input[0][0][1][0], closeTo(127.5, 1));
    expect(input[0][0][1][2], closeTo(127.5, 1));
    expect(input[0][0][2], [0.0, 0.0, 255.0]);

    final downsampleImage = img.Image(width: 4, height: 1)
      ..setPixelRgb(0, 0, 0, 0, 0)
      ..setPixelRgb(1, 0, 100, 100, 100)
      ..setPixelRgb(2, 0, 200, 200, 200)
      ..setPixelRgb(3, 0, 255, 255, 255);
    final downsampled =
        const TfliteClassifierCore().buildEfficientNetInputTensor(
      imageBytes: img.encodePng(downsampleImage),
      inputHeight: 1,
      inputWidth: 3,
    ) as List<List<List<List<double>>>>;
    expect(downsampled[0][0].map((pixel) => pixel[0]).toList(), [30, 150, 239]);
  });

  test('selected crop restricts ranking without inflating probabilities', () {
    final ranked = const TfliteClassifierCore().rankCandidateIndices(
      scores: const [0.82, 0.11, 0.07],
      labels: const [
        'tomato_early_blight',
        'squash_powdery_mildew',
        'tomato_healthy',
      ],
      cropType: 'squash',
    );

    expect(ranked, [1]);
  });

  test(
      'Squash diagnosis prioritizes valid Squash scores over global Eggplant top',
      () {
    final result = const TfliteClassifierCore().responseForScores(
      scores: const [0.85, 0.72, 0.12],
      labels: const [
        'Eggplant_insect_pest',
        'squash_powdery_mildew',
        'squash_healthy',
      ],
      cropType: 'squash',
      preserveProvidedScores: true,
    );

    expect(result.primaryDetection?.label, 'Squash Powdery Mildew');
    expect(result.status, 'ok');
    expect(result.cropType, 'squash');
    expect(result.primaryDetection?.labelKey, 'squash_powdery_mildew');
    expect(result.primaryDetection?.confidence, closeTo(0.72, 1e-12));
    expect(
      result.detections.map((detection) => detection.labelKey),
      everyElement(startsWith('squash_')),
    );
    expect(result.notes.join(' '), contains('Eggplant Insect Pest'));
  });

  test('selected crop with no output classes does not fall back globally', () {
    const scores = [0.82, 0.11, 0.07];
    const labels = [
      'tomato_early_blight',
      'pepper_bacterial_spot',
      'Eggplant_healthy',
    ];
    const core = TfliteClassifierCore();
    final ranked = core.rankCandidateIndices(
      scores: scores,
      labels: labels,
      cropType: 'squash',
    );
    final result = core.responseForScores(
      scores: scores,
      labels: labels,
      cropType: 'squash',
    );

    expect(ranked, isEmpty);
    expect(result.status, 'no_match');
    expect(result.cropType, 'squash');
    expect(result.detections, isEmpty);
    expect(result.notes.join(' '), contains('no output classes'));
  });

  test('active TFLite output indices map to the packaged class labels', () {
    const expectedLabels = [
      'Corn_(maize)___Common_rust_',
      'Corn_(maize)___Cercospora_leaf_spot Gray_leaf_spot',
      'Corn_(maize)___healthy',
      'Corn_(maize)___Northern_Leaf_Blight',
      'Eggplant_healthy',
      'Eggplant_insect_pest',
      'Eggplant_leaf_spot',
      'Eggplant_mosaic_virus',
      'Eggplant_small_leaf',
      'Eggplant_white_mold',
      'Eggplant_wilt',
      'pepper_bacterial_spot',
      'pepper_healthy',
      'squash_powdery_mildew',
      'tomato_bacterial_spot',
      'tomato_early_blight',
      'tomato_healthy',
      'tomato_late_blight',
      'tomato_leaf_mold',
      'tomato_mosaic_virus',
      'tomato_septoria_leaf_spot',
      'tomato_spider_mites',
      'tomato_target_spot',
      'tomato_yellow_leaf_curl_virus',
    ];
    const expectedFamilies = [
      'corn',
      'corn',
      'corn',
      'corn',
      'eggplant',
      'eggplant',
      'eggplant',
      'eggplant',
      'eggplant',
      'eggplant',
      'eggplant',
      'pepper',
      'pepper',
      'squash',
      'tomato',
      'tomato',
      'tomato',
      'tomato',
      'tomato',
      'tomato',
      'tomato',
      'tomato',
      'tomato',
      'tomato',
    ];
    final labels = _packagedLabels;
    const core = TfliteClassifierCore();

    expect(labels, expectedLabels);
    expect(labels.map(core.cropFamilyForLabel).toList(), expectedFamilies);
  });

  test(
      'all four crop families override a higher global score from another family',
      () {
    final labels = _packagedLabels;
    const selectedExamples = <String, String>{
      'tomato': 'tomato_healthy',
      'squash': 'squash_powdery_mildew',
      'pepper': 'pepper_healthy',
      'eggplant': 'Eggplant_healthy',
    };
    const runnerUps = <String, String?>{
      'tomato': 'tomato_early_blight',
      'squash': null,
      'pepper': 'pepper_bacterial_spot',
      'eggplant': 'Eggplant_insect_pest',
    };
    const globalAlternatives = <String, String>{
      'tomato': 'Eggplant_insect_pest',
      'squash': 'Eggplant_insect_pest',
      'pepper': 'Eggplant_insect_pest',
      'eggplant': 'tomato_late_blight',
    };
    const core = TfliteClassifierCore();

    for (final entry in selectedExamples.entries) {
      final scores = List<double>.filled(labels.length, 0.0);
      scores[labels.indexOf(entry.value)] = 0.72;
      scores[labels.indexOf(globalAlternatives[entry.key]!)] = 0.85;
      final runnerUp = runnerUps[entry.key];
      if (runnerUp != null) {
        scores[labels.indexOf(runnerUp)] = 0.12;
      }

      final result = core.responseForScores(
        scores: scores,
        labels: labels,
        cropType: entry.key,
        preserveProvidedScores: true,
      );

      expect(result.status, 'ok', reason: entry.key);
      expect(result.cropType, entry.key, reason: entry.key);
      expect(
        result.primaryDetection?.labelKey,
        entry.value.toLowerCase(),
        reason: entry.key,
      );
      expect(
        result.primaryDetection?.confidence,
        closeTo(0.72, 1e-12),
        reason: '${entry.key} confidence must remain the actual model score',
      );
      expect(
        result.detections.every(
          (detection) =>
              detection.labelKey?.startsWith('${entry.key}_') == true,
        ),
        isTrue,
        reason: '${entry.key} result only includes its own family',
      );
      expect(
        result.notes.join(' '),
        contains('was not used for diagnosis'),
        reason: '${entry.key} retains the global mismatch for diagnostics',
      );
    }
  });

  test('all four crop families return uncertain below the acceptance threshold',
      () {
    final labels = _packagedLabels;
    const selectedExamples = <String, String>{
      'tomato': 'tomato_healthy',
      'squash': 'squash_powdery_mildew',
      'pepper': 'pepper_healthy',
      'eggplant': 'Eggplant_healthy',
    };
    const core = TfliteClassifierCore();

    for (final entry in selectedExamples.entries) {
      final scores = List<double>.filled(labels.length, 0.0);
      scores[labels.indexOf(entry.value)] = 0.69;
      if (entry.key == 'eggplant') {
        scores[labels.indexOf('tomato_late_blight')] = 0.85;
      } else {
        scores[labels.indexOf('Eggplant_insect_pest')] = 0.85;
      }

      final result = core.responseForScores(
        scores: scores,
        labels: labels,
        cropType: entry.key,
        preserveProvidedScores: true,
      );

      expect(result.status, 'no_match', reason: entry.key);
      expect(result.cropType, entry.key, reason: entry.key);
      expect(
        result.primaryDetection?.labelKey,
        entry.value.toLowerCase(),
        reason: entry.key,
      );
      expect(
        result.primaryDetection?.confidence,
        closeTo(0.69, 1e-12),
        reason: entry.key,
      );
      expect(
        result.detections.every(
          (detection) =>
              detection.labelKey?.startsWith('${entry.key}_') == true,
        ),
        isTrue,
        reason: '${entry.key} uncertainty must not fall back globally',
      );
      expect(result.notes.join(' '), contains('below the 70%'));
    }
  });

  test(
      'Squash uncertainty does not fall back to a stronger Eggplant prediction',
      () {
    final labels = _packagedLabels;
    final scores = List<double>.filled(labels.length, 0.0);
    scores[labels.indexOf('Eggplant_insect_pest')] = 0.78;
    scores[labels.indexOf('squash_powdery_mildew')] = 0.15;
    scores[labels.indexOf('tomato_early_blight')] = 0.07;

    final result = const TfliteClassifierCore().responseForScores(
      scores: scores,
      labels: labels,
      cropType: 'squash',
    );

    expect(result.status, 'no_match');
    expect(result.cropType, 'squash');
    expect(result.primaryDetection?.label, 'Squash Powdery Mildew');
    expect(result.primaryDetection?.confidence, closeTo(0.15, 1e-12));
    expect(result.detections, hasLength(1));
    expect(result.notes.join(' '), contains('below the 70%'));
    expect(result.notes.join(' '), contains('Eggplant Insect Pest'));
  });

  test('confidence margin is calculated within the selected family', () {
    final labels = _packagedLabels;
    final scores = List<double>.filled(labels.length, 0.0);
    scores[labels.indexOf('Eggplant_insect_pest')] = 0.85;
    scores[labels.indexOf('tomato_healthy')] = 0.75;
    scores[labels.indexOf('tomato_early_blight')] = 0.60;

    final result = const TfliteClassifierCore().responseForScores(
      scores: scores,
      labels: labels,
      cropType: 'tomato',
      preserveProvidedScores: true,
    );

    expect(result.status, 'no_match');
    expect(result.cropType, 'tomato');
    expect(result.primaryDetection?.labelKey, 'tomato_healthy');
    expect(result.primaryDetection?.confidence, closeTo(0.75, 1e-12));
    expect(
      result.detections.every(
        (detection) => detection.labelKey?.startsWith('tomato_') == true,
      ),
      isTrue,
    );
    expect(result.notes.join(' '), contains('too ambiguous'));
  });

  test('model contract rejects a label and output class mismatch', () {
    expect(
      () => const TfliteClassifierCore().validateModelContract(
        inputShape: const [1, 224, 224, 3],
        outputShape: const [1, 24],
        labelCount: 13,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('does not match 13 labels'),
        ),
      ),
    );
  });

  test('model contract accepts matching image and class tensors', () {
    expect(
      () => const TfliteClassifierCore().validateModelContract(
        inputShape: const [1, 384, 384, 3],
        outputShape: const [1, 24],
        labelCount: 24,
      ),
      returnsNormally,
    );
  });

  test(
    'packaged model tensors match packaged labels',
    () async {
      final labels = (await rootBundle.loadString(
        AppConstants.temporaryScannerLabelsAsset,
      ))
          .split('\n')
          .map((label) => label.trim())
          .where((label) => label.isNotEmpty)
          .toList(growable: false);
      final modelData = await rootBundle.load(
        AppConstants.temporaryScannerModelAsset,
      );
      final modelBytes = modelData.buffer.asUint8List(
        modelData.offsetInBytes,
        modelData.lengthInBytes,
      );
      final interpreter = Interpreter.fromBuffer(modelBytes);
      addTearDown(interpreter.close);

      expect(labels, hasLength(24));
      expect(interpreter.getInputTensor(0).shape, [1, 320, 320, 3]);
      expect(interpreter.getOutputTensor(0).shape, [1, 24]);
      expect(
        () => const TfliteClassifierCore().validateModelContract(
          inputShape: interpreter.getInputTensor(0).shape,
          outputShape: interpreter.getOutputTensor(0).shape,
          labelCount: labels.length,
        ),
        returnsNormally,
      );
    },
    skip: !_validatePackagedAssets,
  );
}
