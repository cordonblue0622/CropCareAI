import 'dart:typed_data';

import 'package:cropcare_ai/services/tflite_classifier_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

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
}
