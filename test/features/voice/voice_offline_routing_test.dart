import 'package:cropcare_ai/data/remote/ai_backend_service.dart';
import 'package:cropcare_ai/features/voice/voice_screen.dart';
import 'package:cropcare_ai/services/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const MethodChannel _permissionChannel =
  MethodChannel('flutter.baseflow.com/permissions/methods');

// ---------------------------------------------------------------------------
// Fake ConnectivityService
// ---------------------------------------------------------------------------

class _FakeConnectivityService extends ConnectivityService {
  _FakeConnectivityService(this._online);
  final bool _online;

  /// Counts how many times [isConnected] was awaited.
  /// A non-zero value proves the offline-check code path ran.
  int isConnectedQueryCount = 0;

  @override
  Future<bool> get isConnected async {
    isConnectedQueryCount++;
    return _online;
  }
}

// ---------------------------------------------------------------------------
// Fake AiBackendService
//
// Uses `implements` instead of `extends` to avoid the SupabaseService field
// initialiser (`Supabase.instance.client`) that runs at construction time and
// would throw in the test environment where Supabase is not initialised.
// ---------------------------------------------------------------------------

class _FakeAiBackendService implements AiBackendService {
  bool transcribeCalled = false;

  @override
  Future<void> warmUpIfNeeded({bool force = false}) async {}

  @override
  Future<AiBackendTranscribeResponse> transcribeAudio({
    required List<int> audioBytes,
    required String filename,
  }) async {
    transcribeCalled = true;
    throw StateError('transcribeAudio must not be called when offline');
  }

  // ---- Unused methods required by the interface ---------------------------

  @override
  String get baseUrl => 'http://localhost:8000';

  @override
  Future<AiBackendChatResponse> sendChatMessage({
    required String userMessage,
    String? cropId,
    dynamic diagnosis,
    List<int>? imageBytes,
    String? imageMimeType,
    List<Map<String, String>> conversationHistory = const [],
    String? locale,
    String? hintCropType,
  }) async =>
      throw UnimplementedError();

  @override
  Future<AiBackendDetectResponse> detectImage({
    required List<int> imageBytes,
    required String filename,
    String? cropType,
  }) async =>
      throw UnimplementedError();

  @override
  Future<AiBackendProgressResponse> assessCropHealth({
    required String cropType,
    required String diseaseName,
    int daysSinceTreatment = 0,
    List<int>? imageBytes,
    String? imageMimeType,
    List<String> completedTasks = const [],
    String? note,
    double? currentHealthScore,
  }) async =>
      throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets(
    'offline mic tap does not invoke backend transcribeAudio',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_permissionChannel, (call) async {
        switch (call.method) {
          case 'checkPermissionStatus':
            return 1;
          case 'requestPermissions':
            final permissions = (call.arguments as List<dynamic>? ?? const []);
            return {
              for (final permission in permissions) permission.toString(): 1,
            };
          case 'shouldShowRequestPermissionRationale':
            return false;
          case 'checkServiceStatus':
            return 1;
          case 'openAppSettings':
            return true;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_permissionChannel, null);
      });

      final fakeAi = _FakeAiBackendService();
      final fakeConnectivity = _FakeConnectivityService(false);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ConnectivityService>.value(
              value: fakeConnectivity,
            ),
            Provider<AiBackendService>.value(value: fakeAi),
          ],
          child: const MaterialApp(home: VoiceScreen()),
        ),
      );
      // VoiceScreen has infinitely repeating AnimationControllers (pulse + wave
      // bars), so pumpAndSettle would time out.  One pump is enough to render
      // the initial frame and make the mic button findable.
      await tester.pump();

      // In the initial (not-listening, not-transcribing) state the mic button
      // shows Icons.mic_none.  When listening it switches to Icons.mic.
      final micButton = find.byIcon(Icons.mic_none);
      expect(
        micButton,
        findsWidgets,
        reason:
            'Mic icon not found — adjust find.byIcon to the actual icon used '
            'in VoiceScreen when idle',
      );

      await tester.tap(micButton.first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Positive assertion: the connectivity check was actually reached.
      // Without this, the test would pass vacuously if the tap threw before
      // ever consulting ConnectivityService (e.g. the offline branch reverted).
      expect(
        fakeConnectivity.isConnectedQueryCount,
        greaterThanOrEqualTo(1),
        reason: 'ConnectivityService.isConnected must be queried at least once '
            'during mic activation to verify the offline-routing code path ran.',
      );

      // Guard: backend must never be called when offline.
      expect(
        fakeAi.transcribeCalled,
        isFalse,
        reason: 'AiBackendService.transcribeAudio must NOT be called when '
            'the device is offline; the screen should fall back to on-device '
            'STT (speech_to_text) instead.',
      );
    },
  );
}
