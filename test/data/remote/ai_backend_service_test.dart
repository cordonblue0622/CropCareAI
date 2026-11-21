import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cropcare_ai/data/remote/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cropcare_ai/data/remote/ai_backend_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoSessionSupabase implements SupabaseService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Session? get currentSession => null;
}

class _HostedBackend extends AiBackendService {
  _HostedBackend(http.Client client)
      : super(supabase: _NoSessionSupabase(), client: client);
  @override
  String get baseUrl => 'https://chat.example.test';
}

void main() {
  test('chat sends every image in one POST without warmup or automatic replay',
      () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/chat');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['image_data_urls'], [
        for (final bytes in [
          [1],
          [2],
          [3],
          [4]
        ])
          'data:image/jpeg;base64,${base64Encode(bytes)}',
      ]);
      return http.Response('{"detail":"AI temporarily unavailable"}', 502);
    });
    addTearDown(client.close);
    await expectLater(
        _HostedBackend(client)
            .sendChatMessage(userMessage: 'Compare', imageBytesList: [
          [1],
          [2],
          [3],
          [4]
        ]),
        throwsA(isA<AiBackendHttpException>().having((error) => error.message,
            'message', 'AI temporarily unavailable')));
    expect(requests, 1);
  });

  test('empty attachment is rejected rather than silently omitted', () async {
    final client = MockClient(
        (request) async => throw StateError('Must not send a partial request'));
    addTearDown(client.close);
    await expectLater(
        _HostedBackend(client)
            .sendChatMessage(userMessage: 'Compare', imageBytesList: [
          [1],
          [],
          [3]
        ]),
        throwsArgumentError);
  });

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
