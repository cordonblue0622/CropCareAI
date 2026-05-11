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
  const VideoPlayerView({super.key, required this.videoSource});

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  VideoPlayerController? _controller;
  bool _initError = false;

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
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _controller = c);
      await c.play();
    } catch (_) {
      if (mounted) setState(() => _initError = true);
    }
  }

  @override
  void dispose() {
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: const Text('Video', style: TextStyle(fontSize: 16)),
        actions: [
          if (_isLocal)
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
    return GestureDetector(
      onTap: () {
        if (c.value.isPlaying) {
          c.pause();
        } else {
          c.play();
        }
        setState(() {});
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
          if (!c.value.isPlaying)
            Container(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(20),
              child: const Icon(Icons.play_arrow,
                  color: Colors.white, size: 44),
            ),
        ],
      ),
    );
  }
}
