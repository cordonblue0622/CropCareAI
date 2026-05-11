import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TextToSpeechService {
  TextToSpeechService._();

  static final TextToSpeechService instance = TextToSpeechService._();

  final FlutterTts _tts = FlutterTts();
  final ValueNotifier<String?> _activeText = ValueNotifier<String?>(null);
  bool _configured = false;

  ValueListenable<String?> get activeTextListenable => _activeText;

  bool isSpeakingText(String text) {
    final normalized = _normalize(text);
    return normalized.isNotEmpty && _activeText.value == normalized;
  }

  Future<void> speak(String text) async {
    final normalized = _normalize(text);
    if (normalized.isEmpty) {
      return;
    }

    await _ensureConfigured();
    if (_activeText.value == normalized) {
      await stop();
      return;
    }

    await _tts.stop();
    _activeText.value = normalized;
    await _tts.speak(normalized);
  }

  Future<void> stop() async {
    await _ensureConfigured();
    _activeText.value = null;
    await _tts.stop();
  }

  Future<void> _ensureConfigured() async {
    if (_configured) {
      return;
    }

    await _tts.awaitSpeakCompletion(true);
    _tts.setCompletionHandler(() => _activeText.value = null);
    _tts.setCancelHandler(() => _activeText.value = null);
    _tts.setErrorHandler((_) => _activeText.value = null);
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _configured = true;
  }

  String _normalize(String text) {
    return text
        .replaceAll(RegExp(r'[`*_#>]'), ' ')
        .replaceAll(RegExp(r'\[(.*?)\]\((.*?)\)'), r'$1')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}