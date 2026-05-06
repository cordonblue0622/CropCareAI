import 'dart:convert';
import 'dart:io';

import 'package:cropcare_ai/services/tflite_classifier_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tflite_flutter/tflite_flutter.dart';

const _imagePath = String.fromEnvironment('TFLITE_IMAGE_PATH');
const _modelPath = String.fromEnvironment('TFLITE_MODEL_PATH');
const _labelsPath = String.fromEnvironment('TFLITE_LABELS_PATH');
const _outputPath = String.fromEnvironment('TFLITE_OUTPUT_PATH');
const _filename = String.fromEnvironment('TFLITE_FILENAME');
const _cropType = String.fromEnvironment('TFLITE_CROP_TYPE');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final missingRequiredInputs = [
    _imagePath,
    _modelPath,
    _labelsPath,
    _outputPath,
  ].any((value) => value.trim().isEmpty);

  test(
    'backend_tflite_detect',
    () async {
      final runtimeDllPath =
          '${Directory(Platform.resolvedExecutable).parent.path}/blobs/libtensorflowlite_c-win.dll';
      print(
        'backend_tflite_detect: resolved executable ${Platform.resolvedExecutable}',
      );
      print(
        'backend_tflite_detect: runtime dll $runtimeDllPath exists=${await File(runtimeDllPath).exists()}',
      );
      print('backend_tflite_detect: tf lite version $version');
      print('backend_tflite_detect: reading inputs');
      final imageBytes = await File(_imagePath).readAsBytes();
      final modelBytes = await File(_modelPath).readAsBytes();
      final rawLabels = await File(_labelsPath).readAsString();
      final labels = rawLabels
          .split('\n')
          .map((label) => label.trim())
          .where((label) => label.isNotEmpty)
          .toList();

      Interpreter? interpreter;
      try {
        print('backend_tflite_detect: opening interpreter');
        interpreter = Interpreter.fromBuffer(modelBytes);
        print('backend_tflite_detect: running inference');
        final response = const TfliteClassifierCore().classifyImage(
          imageBytes: imageBytes,
          filename:
              _filename.trim().isEmpty ? p.basename(_imagePath) : _filename,
          interpreter: interpreter,
          labels: labels,
          cropType: _cropType.trim().isEmpty ? null : _cropType,
          source: 'backend-tflite',
          modelName: 'cropcare_efficientnet_v2',
          modelVersion: 'v2-subset-100',
          modelSource: p.basename(_modelPath),
        );

        print('backend_tflite_detect: writing output');
        final outputFile = File(_outputPath);
        await outputFile.parent.create(recursive: true);
        await outputFile.writeAsString(
          jsonEncode(response.toDetectedRegionsJson()),
        );
        print('backend_tflite_detect: done');
      } finally {
        interpreter?.close();
      }
    },
    skip: missingRequiredInputs
        ? 'Backend TFLite harness only. Provide dart-defines for image, model, labels, and output paths.'
        : false,
  );
}
