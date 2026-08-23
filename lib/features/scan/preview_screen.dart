import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_enums.dart';
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

class _PreviewScreenState extends State<PreviewScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _messageCtrl = TextEditingController();
  CropType? _selectedCropType;
  bool _continuing = false;
  bool _cropSelectionError = false;
  late final AnimationController _cropErrorController;
  late final Animation<double> _cropShakeOffset;

  @override
  void initState() {
    super.initState();
    _cropErrorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _cropShakeOffset = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -5), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -5, end: 0), weight: 1),
    ]).animate(_cropErrorController);
  }

  @override
  void dispose() {
    _cropErrorController.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _continueToChat() async {
    if (_continuing) {
      return;
    }
    if (_selectedCropType == null) {
      setState(() => _cropSelectionError = true);
      _cropErrorController.forward(from: 0);
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
            cropTypeHint: _selectedCropType,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                      const Icon(Icons.circle,
                          color: AppColors.primaryLight, size: 12),
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
                const SizedBox(height: 16),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      color: AppColors.textDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    children: [
                      TextSpan(text: 'What crop is this? '),
                      TextSpan(
                        text: '*',
                        style: TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedBuilder(
                  animation: _cropShakeOffset,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(_cropShakeOffset.value, 0),
                    child: child,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _cropSelectionError
                            ? Colors.red
                            : Colors.transparent,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: CropType.values
                          .map(
                            (cropType) => ChoiceChip(
                              label: Text(
                                _cropTypeLabel(cropType),
                                style: TextStyle(
                                  color: _selectedCropType == cropType
                                      ? Colors.white
                                      : AppColors.primaryDark,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              selected: _selectedCropType == cropType,
                              onSelected: (_) {
                                setState(() {
                                  _selectedCropType = cropType;
                                  _cropSelectionError = false;
                                });
                              },
                              selectedColor: AppColors.primary,
                              backgroundColor: Colors.white,
                              side: BorderSide(
                                color: _selectedCropType == cropType
                                    ? AppColors.primary
                                    : AppColors.primaryLight,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                if (_cropSelectionError) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Choose the crop before continuing.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
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

  String _cropTypeLabel(CropType cropType) {
    final name = cropType.name;
    return '${name[0].toUpperCase()}${name.substring(1)}';
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
