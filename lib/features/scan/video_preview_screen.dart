import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import 'scan_result_screen.dart';

class VideoPreviewScreen extends StatefulWidget {
  final XFile videoFile;
  const VideoPreviewScreen({super.key, required this.videoFile});

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  VideoPlayerController? _controller;
  final TextEditingController _messageCtrl = TextEditingController();
  bool _continuing = false;
  bool _initError = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    try {
      final c = VideoPlayerController.file(File(widget.videoFile.path));
      await c.initialize();
      await c.setLooping(true);
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
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _continueToChat() async {
    if (_continuing) return;
    setState(() => _continuing = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScanResultScreen(
            imageFile: widget.videoFile, // ScanResultScreen treats this as the source XFile
            videoFile: widget.videoFile,
            initialQuery: _messageCtrl.text.trim(),
            openChatOnComplete: true,
            isFromVideo: true,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back,
                    color: AppColors.primaryDark, size: 28),
              ),
              const Spacer(),
              const Text('Video Preview',
                  style: TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 18)),
              const Spacer(),
              const SizedBox(width: 28),
            ]),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _videoArea(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add your first message',
                    style: TextStyle(
                        color: AppColors.textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _messageCtrl,
                  minLines: 2,
                  maxLines: 4,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText:
                        'Tell the AI what you noticed before sending this video...',
                    hintStyle: const TextStyle(color: AppColors.textLightGray),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.all(16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primaryLight),
                    foregroundColor: AppColors.textDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Retake',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _continuing ? null : _continueToChat,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _continuing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward, size: 18),
                  label: Text(
                    _continuing ? 'Opening chat...' : 'Continue',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _videoArea() {
    if (_initError) {
      return Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Could not play this video. Try recording again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: AppColors.primary),
      );
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
              padding: const EdgeInsets.all(16),
              child: const Icon(Icons.play_arrow,
                  color: Colors.white, size: 36),
            ),
        ],
      ),
    );
  }
}
