import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import 'scan_result_screen.dart';

class PreviewScreen extends StatefulWidget {
  final XFile imageFile;
  final Uint8List imageBytes;
  final bool isFromVideo;

  const PreviewScreen({
    super.key,
    required this.imageFile,
    required this.imageBytes,
    this.isFromVideo = false,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final TextEditingController _messageCtrl = TextEditingController();
  bool _continuing = false;

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _continueToChat() async {
    if (_continuing) {
      return;
    }

    setState(() => _continuing = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScanResultScreen(
            imageFile: widget.imageFile,
            imageBytes: widget.imageBytes,
            initialQuery: _messageCtrl.text.trim(),
            openChatOnComplete: true,
            isFromVideo: widget.isFromVideo,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _continuing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      body: SafeArea(
        child: Column(children: [
          // Top bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back,
                    color: AppColors.primaryDark, size: 28),
              ),
              const Spacer(),
              const Text('Preview',
                  style: TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 18)),
              const Spacer(),
              const SizedBox(width: 28),
            ]),
          ),

          const SizedBox(height: 24),

          // Image card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Stack(alignment: Alignment.topRight, children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 16)
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _MemoryImageView(
                      widget.imageBytes,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.circle, color: AppColors.primaryLight, size: 12),
                      const SizedBox(width: 4),
                      Text(widget.isFromVideo ? 'VIDEO FRAME' : 'HD CAPTURE',
                          style: const TextStyle(
                              color: AppColors.primaryDark,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),

          const SizedBox(height: 20),

          // Ready pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary.withOpacity(0.4)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle, color: AppColors.primaryDark, size: 16),
              SizedBox(width: 6),
              Text('Image Captured',
                  style: TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ]),
          ),

          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add your first message',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _messageCtrl,
                  minLines: 2,
                  maxLines: 4,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText:
                        'Tell the AI what you noticed before sending this photo...',
                    hintStyle: const TextStyle(color: AppColors.textLightGray),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.all(16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: AppColors.primaryDark.withOpacity(0.08),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Buttons
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
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
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
}

class _MemoryImageView extends StatelessWidget {
  final Uint8List imageBytes;
  final BoxFit fit;
  final double? width;

  const _MemoryImageView(
    this.imageBytes, {
    required this.fit,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      imageBytes,
      fit: fit,
      width: width,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Container(
        width: width,
        color: Colors.black26,
        alignment: Alignment.center,
        child: const Text(
          'Preview unavailable',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}
