import 'package:cropcare_ai/data/remote/ai_backend_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiBackendService.resolveBaseUrl', () {
    test('uses configured base URL before platform defaults', () {
      expect(
        AiBackendService.resolveBaseUrl(
          configuredBaseUrl: ' http://192.168.1.8:8000/ ',
          configuredAndroidBaseUrl: 'http://10.0.2.2:8000',
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        'http://192.168.1.8:8000',
      );
    });

    test('uses Android-specific backend URL for physical-device builds', () {
      expect(
        AiBackendService.resolveBaseUrl(
          configuredBaseUrl: '',
          configuredAndroidBaseUrl: 'http://192.168.1.8:8000/',
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        'http://192.168.1.8:8000',
      );
    });

    test('keeps emulator default when no Android override is configured', () {
      expect(
        AiBackendService.resolveBaseUrl(
          configuredBaseUrl: '',
          configuredAndroidBaseUrl: '',
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        'http://10.0.2.2:8000',
      );
    });
  });
}
