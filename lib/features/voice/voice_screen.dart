import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/remote/ai_backend_service.dart';
import '../../services/connectivity_service.dart';
import '../chat/screens/chat_screen.dart';
import '../scan/scan_screen.dart';

const List<String> _exampleCommands = [
  'Scan this crop',
  'What disease is this?',
  'Give me treatment steps',
  'Open AI chat',
  'Show diagnosis help',
];

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen>
    with TickerProviderStateMixin {
  late SpeechToText _speech;
  final AudioRecorder _recorder = AudioRecorder();
  bool _available = false;
  bool _listening = false;
  bool _transcribing = false;
  bool _usingSpeechFallback = false;
  bool _speechInitializing = false;
  // Prevents double-navigation when speech_to_text fires both
  // 'done' and 'notListening' status events for the same session.
  bool _commandHandled = false;
  String _words = '';
  String? _errorText;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _speech = SpeechToText();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 1.18).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _initSpeech();
  }

  Future<bool> _initSpeech({bool recreate = false}) async {
    if (_speechInitializing) {
      return _available;
    }
    _speechInitializing = true;
    if (recreate) {
      _speech = SpeechToText();
    }
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _listening = false);
            if (_usingSpeechFallback && !_commandHandled) {
              final transcript = _words.trim();
              if (transcript.isNotEmpty) {
                _commandHandled = true;
                _handleCommand(transcript);
              } else if (mounted) {
                setState(() {
                  _errorText = 'No speech was detected. Try again.';
                });
              }
            }
          }
        },
        onError: (error) {
          if (!mounted) return;
          final message = error.toString().toLowerCase();
          setState(() {
            _listening = false;
            if (message.contains('no match') || message.contains('no_speech')) {
              _errorText = 'No speech was detected. Try again.';
            } else if (!message.contains('busy')) {
              _errorText =
                  'Voice recognition was interrupted. Tap the mic and try again.';
            }
          });
        },
      );
      _available = available;
      if (mounted) {
        setState(() {});
      }
      return available;
    } finally {
      _speechInitializing = false;
    }
  }

  Future<bool> _ensureSpeechAvailable() async {
    if (_available) {
      return true;
    }
    return _initSpeech(recreate: true);
  }

  Future<bool> _ensureMicrophonePermission() async {
    final currentStatus = await Permission.microphone.status;
    if (currentStatus.isGranted) {
      return true;
    }

    final requestedStatus = await Permission.microphone.request();
    return requestedStatus.isGranted;
  }

  Future<void> _toggleListen() async {
    if (_transcribing) return;
    if (_listening) {
      if (_usingSpeechFallback) {
        await _speech.stop();
        if (mounted) {
          setState(() => _listening = false);
        }
      } else {
        await _stopRecordingAndTranscribe();
      }
    } else {
      await _startVoiceCapture();
    }
  }

  Future<void> _startVoiceCapture() async {
    setState(() {
      _errorText = null;
      _words = '';
    });

    final hasMicrophonePermission = await _ensureMicrophonePermission();
    if (!hasMicrophonePermission) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Microphone permission is required to use voice features.';
      });
      return;
    }

    final connectivityService = context.read<ConnectivityService>();
    bool isOnline;
    try {
      isOnline = await connectivityService.isConnected;
    } catch (_) {
      isOnline = false;
    }

    final localSpeechStarted = await _startSpeechFallback(
      isOnline
          ? 'Using device speech recognition.'
          : 'You are offline. Using on-device speech recognition.',
      onDevice: true,
    );
    if (localSpeechStarted) {
      return;
    }

    if (!isOnline) {
      if (!mounted) return;
      setState(() {
        _errorText =
            'Offline voice needs speech recognition support on this device. If it is unavailable, reconnect to use backend transcription.';
      });
      return;
    }

    try {
      final hasRecorderPermission = await _recorder.hasPermission();
      if (!hasRecorderPermission) {
        if (!mounted) return;
        setState(() {
          _errorText =
              'Microphone access is unavailable for backend transcription on this device.';
        });
        return;
      }

      final recordingPath = await _buildRecordingPath();
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 128000,
        ),
        path: recordingPath,
      );

      if (!mounted) return;
      setState(() {
        _listening = true;
        _usingSpeechFallback = false;
        _errorText = 'Recording for backend transcription.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText =
            'Backend voice capture is unavailable right now, and local speech recognition could not start.';
      });
    }
  }

  Future<bool> _startSpeechFallback(
    String message, {
    bool onDevice = false,
  }) async {
    if (!await _ensureSpeechAvailable()) {
      if (!mounted) return false;
      setState(() {
        _listening = false;
        _usingSpeechFallback = false;
        _errorText =
            'Microphone or speech recognition is unavailable on this device.';
      });
      return false;
    }

    if (!mounted) return false;
    setState(() {
      _listening = true;
      _usingSpeechFallback = true;
      _commandHandled = false;
      _errorText = message;
      _words = '';
    });

    Future<bool> startListening({required bool useOnDevice}) async {
      try {
        final didStart = await _speech.listen(
      onResult: (result) {
        final transcript = result.recognizedWords.trim();
        if (mounted) {
          setState(() => _words = transcript);
        }
        if (_usingSpeechFallback &&
            result.finalResult &&
            transcript.isNotEmpty &&
            !_commandHandled) {
          _commandHandled = true;
          if (mounted) {
            setState(() => _listening = false);
          }
          _handleCommand(transcript);
        }
      },
      listenFor: const Duration(minutes: 2),
      pauseFor: const Duration(seconds: 8),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        autoPunctuation: true,
        listenMode: ListenMode.dictation,
        onDevice: useOnDevice,
      ),
        );
        return didStart;
      } catch (_) {
        return false;
      }
    }

    var didStart = await startListening(useOnDevice: onDevice);
    if (!didStart && onDevice) {
      await _initSpeech(recreate: true);
      didStart = await startListening(useOnDevice: false);
      if (didStart && mounted) {
        setState(() {
          _errorText =
              'Offline voice switched to the device speech recognizer because strict on-device mode is unavailable here.';
        });
      }
    }

    if (!didStart && mounted) {
      setState(() {
        _listening = false;
        _usingSpeechFallback = false;
        _errorText = 'Could not start voice recognition. Try again.';
      });
    }

    return didStart;
  }

  Future<String> _buildRecordingPath() async {
    final tempDir = await getTemporaryDirectory();
    return path.join(
      tempDir.path,
      'voice-command-${DateTime.now().millisecondsSinceEpoch}.wav',
    );
  }

  Future<void> _stopRecordingAndTranscribe() async {
    final recordingPath = await _recorder.stop();

    if (!mounted) return;
    setState(() {
      _listening = false;
      _transcribing = true;
    });

    if (recordingPath == null || recordingPath.trim().isEmpty) {
      setState(() {
        _transcribing = false;
        _errorText = 'No audio was captured. Try again.';
      });
      return;
    }

    try {
      final audioBytes = await XFile(recordingPath).readAsBytes();
      final parsedPath = Uri.tryParse(recordingPath);
      final normalizedPath =
          parsedPath != null && parsedPath.path.isNotEmpty ? parsedPath.path : recordingPath;
      final filename = path.basename(normalizedPath).trim().isEmpty
          ? 'voice-command.wav'
          : path.basename(normalizedPath);
      final transcriptResponse = await context.read<AiBackendService>().transcribeAudio(
            audioBytes: audioBytes,
            filename: filename,
          );
      final transcript = transcriptResponse.transcript.trim();

      if (!mounted) return;
      setState(() {
        _transcribing = false;
        _words = transcript;
        _errorText = transcript.isEmpty
            ? 'No speech was detected. Try again.'
            : null;
      });

      if (transcript.isNotEmpty) {
        _handleCommand(transcript);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _transcribing = false;
        _errorText =
            'Voice transcription failed. Check the backend connection and try again.';
      });
    }
  }

  void _handleCommand(String text) {
    if (text.isEmpty) return;
    final lower = text.toLowerCase();
    if (lower.contains('scan') ||
        lower.contains('capture') ||
        lower.contains('image') ||
        lower.contains('photo') ||
        lower.contains('diagnos')) {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const ScanScreen()));
    } else {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ChatScreen(
                    startFreshSession: true,
                    initialQuery: text,
                  )));
    }
  }

  @override
  void dispose() {
    _speech.stop();
    unawaited(_recorder.dispose());
    _pulseCtrl.dispose();
    super.dispose();
  }

  String get _promptText {
    if (_transcribing) {
      return 'Transcribing with Whisper...';
    }
    if (_words.isNotEmpty) {
      return _words;
    }
    if (_listening && _usingSpeechFallback) {
      return 'Listening with device speech recognition...';
    }
    if (_listening) {
      return 'Recording your voice command...';
    }
    return 'Tap the mic to speak';
  }

  String get _statusText {
    if (_transcribing) {
      return 'Sending audio to Whisper';
    }
    if (_listening && _usingSpeechFallback) {
      return 'Listening locally';
    }
    if (_listening) {
      return 'Tap to stop recording';
    }
    return 'Tap to speak';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('VOICE ASSISTANT',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text('CropCare AI',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _listening
                      ? Colors.red.withOpacity(0.85)
                      : AppColors.primary.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                      _listening ? Icons.radio_button_on : Icons.radio_button_off,
                      size: 10,
                      color: Colors.white),
                  const SizedBox(width: 5),
                  Text(_listening ? 'ACTIVE' : 'STANDBY',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),

          const Spacer(),

          // Waveform animation
          SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                15,
                (i) => _WaveBar(isAnimating: _listening, index: i),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Recognised text
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _promptText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _words.isEmpty ? Colors.white70 : Colors.white,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorText!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFFD8D8),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 40),

          // Mic button
          GestureDetector(
            onTap: _transcribing ? null : _toggleListen,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, child) => Transform.scale(
                scale: _listening ? _pulse.value : 1.0,
                child: child,
              ),
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _transcribing
                      ? Colors.orange
                      : _listening
                          ? Colors.red
                          : AppColors.primary,
                  boxShadow: [
                    BoxShadow(
                      color: (_transcribing
                              ? Colors.orange
                              : _listening
                                  ? Colors.red
                                  : AppColors.primary)
                          .withOpacity(0.4),
                      blurRadius: 24,
                      spreadRadius: 4,
                    )
                  ],
                ),
                child: Icon(
                  _transcribing
                      ? Icons.graphic_eq
                      : _listening
                          ? Icons.mic
                          : Icons.mic_none,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _statusText,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),

          const SizedBox(height: 40),

          // Command chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: _exampleCommands
                  .map((cmd) => _ExampleCommandPill(
                        label: cmd,
                        onTap: () => _handleCommand(cmd),
                      ))
                  .toList(),
            ),
          ),

          const Spacer(),
        ]),
      ),
    );
  }
}

class _WaveBar extends StatefulWidget {
  final bool isAnimating;
  final int index;
  const _WaveBar({required this.isAnimating, required this.index});

  @override
  State<_WaveBar> createState() => _WaveBarState();
}

class _WaveBarState extends State<_WaveBar> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    final duration = Duration(milliseconds: 400 + widget.index * 60);
    _ctrl = AnimationController(vsync: this, duration: duration)
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 4, end: 40).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(_WaveBar old) {
    super.didUpdateWidget(old);
    if (widget.isAnimating != old.isAnimating) {
      if (widget.isAnimating) {
        _ctrl.repeat(reverse: true);
      } else {
        _ctrl.animateTo(0.1);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 4,
        height: widget.isAnimating ? _anim.value : 4,
        decoration: BoxDecoration(
          color: AppColors.primaryLight.withOpacity(0.7),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _ExampleCommandPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ExampleCommandPill({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
