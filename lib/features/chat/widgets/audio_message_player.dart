import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class AudioMessagePlayer extends StatefulWidget {
  final String audioPath;
  final bool isUser;

  const AudioMessagePlayer({
    super.key,
    required this.audioPath,
    required this.isUser,
  });

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _fileMissing = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final exists = await File(widget.audioPath).exists();
    if (!exists) {
      if (mounted) {
        setState(() => _fileMissing = true);
      }
      return;
    }

    await _player.setReleaseMode(ReleaseMode.stop);
    _positionSub = _player.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() => _position = position);
      }
    });
    _durationSub = _player.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() => _duration = duration);
      }
    });
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPlaying = state == PlayerState.playing;
        if (state == PlayerState.stopped) {
          _position = Duration.zero;
        }
      });
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_fileMissing) {
      return;
    }

    if (_isPlaying) {
      await _player.pause();
      return;
    }

    if (_position > Duration.zero && _position < _duration) {
      await _player.resume();
      return;
    }

    await _player.play(DeviceFileSource(widget.audioPath));
  }

  Future<void> _stopPlayback() async {
    if (_fileMissing) {
      return;
    }
    await _player.stop();
    if (mounted) {
      setState(() => _position = Duration.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor = widget.isUser ? AppColors.primary : Colors.white;
    final iconColor = widget.isUser ? Colors.white : AppColors.primary;
    final textColor = widget.isUser ? Colors.white70 : AppColors.textGray;
    final activeColor = widget.isUser ? Colors.white : AppColors.primary;
    final safeDuration = _duration.inMilliseconds <= 0
        ? const Duration(seconds: 1)
        : _duration;
    final safePosition = _position > safeDuration ? safeDuration : _position;

    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: _fileMissing
          ? Text(
              'Voice recording unavailable on this device.',
              style: TextStyle(color: textColor, fontSize: 13),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _togglePlayback,
                      icon: Icon(
                        _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                        color: iconColor,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Voice message',
                        style: TextStyle(
                          color: widget.isUser ? Colors.white : AppColors.textDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _stopPlayback,
                      icon: Icon(
                        Icons.stop_circle_outlined,
                        color: iconColor,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: activeColor,
                    inactiveTrackColor:
                        widget.isUser ? Colors.white38 : Colors.black12,
                    thumbColor: activeColor,
                    overlayColor: activeColor.withOpacity(0.15),
                  ),
                  child: Slider(
                    value: safePosition.inMilliseconds
                        .clamp(0, safeDuration.inMilliseconds)
                        .toDouble(),
                    min: 0,
                    max: safeDuration.inMilliseconds.toDouble(),
                    onChanged: (value) {
                      setState(() {
                        _position = Duration(milliseconds: value.round());
                      });
                    },
                    onChangeEnd: (value) {
                      _player.seek(Duration(milliseconds: value.round()));
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(safePosition),
                      style: TextStyle(color: textColor, fontSize: 11),
                    ),
                    Text(
                      _formatDuration(_duration),
                      style: TextStyle(color: textColor, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}