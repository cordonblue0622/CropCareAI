import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/local/database_helper.dart';
import '../../../services/video_cleanup_service.dart';

/// Fullscreen video player with a delete button in the app bar.
/// Pops with `true` if the user deleted the video, `null` otherwise.
class VideoPlayerView extends StatefulWidget {
  final String videoSource; // local path OR http(s) url
  final bool autoplay;
  final bool showDeleteAction;
  final bool inline;

  const VideoPlayerView({
    super.key,
    required this.videoSource,
    this.autoplay = false,
    this.showDeleteAction = true,
    this.inline = false,
  });

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  VideoPlayerController? _controller;
  bool _initError = false;
  bool _showControls = true;

  bool get _isLocal =>
      !widget.videoSource.startsWith('http://') &&
      !widget.videoSource.startsWith('https://');

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    try {
      final c = _isLocal
          ? VideoPlayerController.file(File(widget.videoSource))
          : VideoPlayerController.networkUrl(Uri.parse(widget.videoSource));
      await c.initialize();
      await c.setLooping(false);
      if (!mounted) {
        c.dispose();
        return;
      }
      c.addListener(_onVideoTick);
      setState(() => _controller = c);
      if (widget.autoplay) {
        await c.play();
      }
    } catch (_) {
      if (mounted) setState(() => _initError = true);
    }
  }

  void _onVideoTick() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _pauseIfPlaying() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    }
  }

  @override
  void deactivate() {
    unawaited(_pauseIfPlaying());
    super.deactivate();
  }

  @override
  void dispose() {
    unawaited(_pauseIfPlaying());
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this video?'),
        content: const Text(
            'The video file will be removed from this device. The diagnosis details and treatment recommendations will be kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final db = context.read<DatabaseHelper>();
    final svc = VideoCleanupService(db: db);
    await svc.deleteVideo(widget.videoSource);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inline) {
      return _body();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: const Text('Video', style: TextStyle(fontSize: 16)),
        actions: [
          if (_isLocal && widget.showDeleteAction)
            IconButton(
              tooltip: 'Delete video',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Center(child: _body()),
    );
  }

  Widget _body() {
    if (_initError) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Could not play this video.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const CircularProgressIndicator(color: AppColors.primary);
    }
    final duration = c.value.duration;
    final position = c.value.position > duration ? duration : c.value.position;

    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.inline ? 18 : 0),
        child: Container(
          color: Colors.black,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
              if (_showControls)
                Positioned.fill(
                  child: Container(
                    color: Colors.black26,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(height: 12),
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            iconSize: 44,
                            color: Colors.white,
                            icon: Icon(
                              c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                            ),
                            onPressed: () async {
                              if (c.value.isPlaying) {
                                await c.pause();
                              } else {
                                await c.play();
                              }
                              if (mounted) {
                                setState(() {});
                              }
                            },
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                          color: Colors.black54,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              VideoProgressIndicator(
                                c,
                                allowScrubbing: true,
                                colors: const VideoProgressColors(
                                  playedColor: AppColors.primary,
                                  bufferedColor: Colors.white38,
                                  backgroundColor: Colors.white24,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${_formatDuration(position)} / ${_formatDuration(duration)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'Stop video',
                                    icon: const Icon(
                                      Icons.stop_circle_outlined,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    onPressed: () async {
                                      await c.pause();
                                      await c.seekTo(Duration.zero);
                                      if (mounted) {
                                        setState(() {});
                                      }
                                    },
                                  ),
                                  if (!widget.inline && _isLocal && widget.showDeleteAction)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        tooltip: 'Delete video',
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        onPressed: _confirmDelete,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
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
