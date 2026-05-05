import 'dart:convert';
import 'dart:io';

import 'package:cropcare_ai/services/tflite_classifier_core.dart';
import 'package:path/path.dart' as p;
import 'package:tflite_flutter/tflite_flutter.dart';

Future<void> main(List<String> args) async {
  Interpreter? interpreter;
  try {
    final options = _parseArgs(args);
    final imagePath = options['image'];
    final modelPath = options['model'];
    final labelsPath = options['labels'];

    if (imagePath == null || modelPath == null || labelsPath == null) {
      stderr.writeln(
        'Usage: flutter pub run tool/backend_tflite_detect.dart --image <path> --model <path> --labels <path> [--filename <name>] [--crop-type <value>]',
      );
      exitCode = 64;
      return;
    }

    final imageBytes = await File(imagePath).readAsBytes();
    final modelBytes = await File(modelPath).readAsBytes();
    final rawLabels = await File(labelsPath).readAsString();
    final labels = rawLabels
        .split('\n')
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList();

    interpreter = Interpreter.fromBuffer(modelBytes);

    final response = const TfliteClassifierCore().classifyImage(
      imageBytes: imageBytes,
      filename: options['filename'] ?? p.basename(imagePath),
      interpreter: interpreter,
      labels: labels,
      cropType: options['crop-type'],
      source: 'backend-tflite',
      modelName: 'cropcare_efficientnet_with_eggplant',
      modelVersion: 'temporary-v1',
      modelSource: p.basename(modelPath),
    );

    stdout.writeln(jsonEncode(response.toDetectedRegionsJson()));
  } catch (error, stackTrace) {
    stderr.writeln('TFLite backend helper failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    interpreter?.close();
  }
}

Map<String, String> _parseArgs(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final current = args[i];
    if (!current.startsWith('--')) {
      continue;
    }
    final key = current.substring(2);
    if (i + 1 >= args.length) {
      break;
    }
    options[key] = args[i + 1];
    i++;
  }
  return options;
}