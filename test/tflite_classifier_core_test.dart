
import 'package:cropcare_ai/core/constants/app_constants.dart';
import 'package:cropcare_ai/services/tflite_classifier_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

const _validatePackagedAssets = bool.fromEnvironment('TFLITE_VALIDATE_ASSETS');

void main() {
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

  testWidgets(
    'packaged model tensors match packaged labels',
    (tester) async {
      final labels = (await rootBundle.loadString(
        AppConstants.temporaryScannerLabelsAsset,
      ))
          .split('\n')
          .map((label) => label.trim())
          .where((label) => label.isNotEmpty)
          .toList(growable: false);
      final interpreter = await Interpreter.fromAsset(
        AppConstants.temporaryScannerModelAsset,
      );
      addTearDown(interpreter.close);

      expect(labels, hasLength(24));
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
