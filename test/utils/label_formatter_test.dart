import 'package:flutter_test/flutter_test.dart';
import 'package:cropcare_ai/core/utils/label_formatter.dart';

void main() {
  group('humanizeDiseaseLabel', () {
    test('converts snake_case to Title Case', () {
      expect(humanizeDiseaseLabel('tomato_bacterial_spot'),
          'Tomato Bacterial Spot');
      expect(humanizeDiseaseLabel('tomato_early_blight'),
          'Tomato Early Blight');
      expect(humanizeDiseaseLabel('pepper_bell_healthy'),
          'Pepper Bell Healthy');
    });

    test('handles single token', () {
      expect(humanizeDiseaseLabel('healthy'), 'Healthy');
      expect(humanizeDiseaseLabel('TOMATO'), 'Tomato');
    });

    test('is idempotent on already-humanized strings', () {
      expect(humanizeDiseaseLabel('Tomato Bacterial Spot'),
          'Tomato Bacterial Spot');
    });

    test('collapses multiple separators', () {
      expect(humanizeDiseaseLabel('tomato___bacterial  spot'),
          'Tomato Bacterial Spot');
    });

    test('returns empty for empty input', () {
      expect(humanizeDiseaseLabel(''), '');
    });

    test('trims surrounding whitespace and underscores', () {
      expect(humanizeDiseaseLabel('  _tomato_blight_ '), 'Tomato Blight');
    });

    test('preserves digits inside tokens', () {
      expect(humanizeDiseaseLabel('crop_v2_label'), 'Crop V2 Label');
    });
  });
}
