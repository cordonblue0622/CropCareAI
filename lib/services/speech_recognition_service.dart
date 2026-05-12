import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart' as stt;

typedef SpeechStatusCallback = void Function(String status);
typedef SpeechErrorCallback = void Function(String errorMessage);
typedef SpeechResultCallback = void Function(String transcript, bool isFinal);

class SpeechRecognitionService {
  factory SpeechRecognitionService() => _instance;

  SpeechRecognitionService._internal();

  static final SpeechRecognitionService _instance =
      SpeechRecognitionService._internal();

  stt.SpeechToText _speech = stt.SpeechToText();
  SpeechStatusCallback? _onStatus;
  SpeechErrorCallback? _onError;
  bool _available = false;
  bool _initializing = false;

  bool get isListening => _speech.isListening;
  bool get isAvailable => _available;

  Future<bool> initialize({
    required SpeechStatusCallback onStatus,
    required SpeechErrorCallback onError,
    bool recreate = false,
  }) async {
    if (_initializing) {
      return _available;
    }

    _initializing = true;
    _onStatus = onStatus;
    _onError = onError;

    if (recreate) {
      _speech = stt.SpeechToText();
    }

    try {
      final available = await _speech.initialize(
        onStatus: onStatus,
        onError: (error) {
          final message = error.errorMsg.trim().isEmpty
              ? error.toString()
              : error.errorMsg.trim();
          onError(message);
        },
      );
      _available = available;
      return available;
    } finally {
      _initializing = false;
    }
  }

  Future<bool> ensureReady() async {
    final onStatus = _onStatus;
    final onError = _onError;
    if (onStatus == null || onError == null) {
      return false;
    }

    if (_available) {
      return true;
    }

    return initialize(
      onStatus: onStatus,
      onError: onError,
      recreate: true,
    );
  }

  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }

  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } catch (_) {}
  }

  Future<void> reset({bool recreate = false}) async {
    await stop();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await cancel();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    if (!recreate) {
      return;
    }

    final onStatus = _onStatus;
    final onError = _onError;
    if (onStatus == null || onError == null) {
      return;
    }

    _available = false;
    await initialize(
      onStatus: onStatus,
      onError: onError,
      recreate: true,
    );
  }

  Future<bool> startDictation({
    required SpeechResultCallback onResult,
    bool preferOnDevice = false,
  }) async {
    if (!await ensureReady()) {
      return false;
    }

    Future<bool> attempt({required bool onDevice}) async {
      try {
        return await _speech.listen(
          onResult: (result) {
            onResult(result.recognizedWords.trim(), result.finalResult);
          },
          listenFor: const Duration(minutes: 2),
          pauseFor: const Duration(seconds: 8),
          listenOptions: stt.SpeechListenOptions(
            cancelOnError: true,
            partialResults: true,
            autoPunctuation: true,
            listenMode: stt.ListenMode.dictation,
            onDevice: onDevice,
          ),
        );
      } catch (_) {
        return false;
      }
    }

    var didStart = await attempt(onDevice: preferOnDevice);
    if (didStart) {
      return true;
    }

    await reset(recreate: true);
    didStart = await attempt(onDevice: !preferOnDevice);
    if (didStart) {
      return true;
    }

    await reset(recreate: true);
    return false;
  }

  void dispose() {
    unawaited(cancel());
  }
}