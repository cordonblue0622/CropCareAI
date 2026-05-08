import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import 'preview_screen.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'video_preview_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  static const Duration _maxVideoDuration = Duration(seconds: 15);

  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _initializing = true;
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  String? _error;
  final ImagePicker _picker = ImagePicker();

  bool get _isSecureWebContext {
    if (!kIsWeb) {
      return true;
    }

    final uri = Uri.base;
    return uri.scheme == 'https' ||
        uri.host == 'localhost' ||
        uri.host == '127.0.0.1';
  }

  Future<void> _pickFallbackImage() async {
    if (kIsWeb) {
      await _pickFromGallery();
      return;
    }

    await _pickFromCamera();
  }

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (kIsWeb && !_isSecureWebContext) {
      setState(() {
        _error =
            'Live camera preview requires HTTPS or localhost in the browser. Use Choose Photo instead.';
        _initializing = false;
      });
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _error = 'No camera available on this device.';
          _initializing = false;
        });
        return;
      }
      _controller = CameraController(
        _cameras!.first,
        ResolutionPreset.high,
        enableAudio: !kIsWeb,
      );
      await _controller!.initialize();
      if (mounted) setState(() => _initializing = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = kIsWeb
              ? 'Browser camera preview is unavailable right now. Use Choose Photo instead.'
              : 'Camera error: ${e.toString()}';
          _initializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      await _pickFallbackImage();
      return;
    }
    try {
      final file = await _controller!.takePicture();
      await _openPreview(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Capture failed: $e')));
      }
    }
  }

  Future<void> _toggleVideo() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      await _controller!.prepareForVideoRecording();
      await _controller!.startVideoRecording();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start recording: $e')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _recordingSeconds = 0;
    });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _recordingSeconds++);
      if (_recordingSeconds >= _maxVideoDuration.inSeconds) {
        // Auto-stop at the cap.
        _stopRecording();
      }
    });
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    XFile? rawFile;
    try {
      rawFile = await _controller!.stopVideoRecording();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not finalize recording: $e')),
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _recordingSeconds = 0;
    });

    if (rawFile == null) return;

    final saved = await _persistRecording(rawFile);
    if (saved == null || !mounted) return;
    await _openVideoPreview(saved);
  }

  /// Move the camera-package's temp recording into `<app docs>/videos/<uuid>.mp4`.
  /// Returns the persisted XFile or null on failure.
  Future<XFile?> _persistRecording(XFile rawFile) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final videosDir = Directory('${docs.path}/videos');
      if (!await videosDir.exists()) {
        await videosDir.create(recursive: true);
      }
      final id = const Uuid().v4();
      final destPath = '${videosDir.path}/$id.mp4';
      final source = File(rawFile.path);
      await source.copy(destPath);
      try {
        await source.delete();
      } catch (_) {/* tolerate temp-file lock on some Android devices */}
      return XFile(destPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save video: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _openVideoPreview(XFile videoFile) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPreviewScreen(videoFile: videoFile),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _pickFromGallery() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    await _openPreview(file);
  }

  Future<void> _pickFromCamera() async {
    if (kIsWeb) {
      await _pickFromGallery();
      return;
    }

    try {
      final file = await _picker.pickImage(source: ImageSource.camera);
      await _openPreview(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera capture failed: $e')),
        );
      }
    }
  }

  Future<void> _openPreview(XFile? file, {bool isFromVideo = false}) async {
    if (file == null || !mounted) {
      return;
    }

    try {
      final imageBytes = await file.readAsBytes();
      if (!mounted) {
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(
            imageFile: file,
            imageBytes: imageBytes,
            isFromVideo: isFromVideo,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to open preview: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          // Camera preview or fallback
          if (_initializing)
            const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.camera_alt,
                        color: Colors.white38, size: 64),
                    const SizedBox(height: 16),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _pickFallbackImage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary),
                      icon: const Icon(
                        kIsWeb ? Icons.upload_file : Icons.photo_camera,
                        color: Colors.white,
                      ),
                      label: const Text(
                        kIsWeb ? 'Choose Photo' : 'Take Photo',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    if (!kIsWeb) ...[
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _pickFromGallery,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary),
                        icon: const Icon(Icons.photo_library, color: Colors.white),
                        label: const Text('Upload from Gallery',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else if (_controller != null && _controller!.value.isInitialized)
            Positioned.fill(child: CameraPreview(_controller!))
          else
            const SizedBox.shrink(),

          // Corner brackets overlay
          if (!_initializing && _error == null)
            Positioned.fill(child: _CornerOverlay()),

          // Recording timer overlay
          if (_isRecording)
            Positioned(
              top: 86,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fiber_manual_record,
                          color: Colors.red, size: 10),
                      const SizedBox(width: 6),
                      Text(
                        'REC  ${_formatDuration(_recordingSeconds)}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.close,
                        color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('CropCare AI',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text('AI DIAGNOSTIC ACTIVE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ]),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    if (_cameras != null && _cameras!.length > 1 && _controller != null) {
                      final current = _controller!.description;
                      final next = _cameras!.firstWhere(
                          (c) => c.lensDirection != current.lensDirection,
                          orElse: () => current);
                      _controller = CameraController(next, ResolutionPreset.high);
                      await _controller!.initialize();
                      if (mounted) setState(() {});
                    }
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.flip_camera_ios,
                        color: Colors.white, size: 20),
                  ),
                ),
              ]),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Column(children: [
              // Tip
              if (!_initializing && _error == null)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Center the affected plant area within the frame',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Video button
                  _ControlBtn(
                    icon: _isRecording ? Icons.stop : Icons.videocam,
                    label: _isRecording ? 'STOP' : 'VIDEO',
                    color: _isRecording ? Colors.red : Colors.white,
                    onTap: _error == null ? _toggleVideo : _pickFallbackImage,
                  ),

                  // Capture button
                  GestureDetector(
                    onTap: _capture,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        color: Colors.transparent,
                      ),
                      child: Center(
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Upload button
                  _ControlBtn(
                    icon: Icons.upload_file,
                    label: kIsWeb ? 'PHOTO' : 'UPLOAD',
                    color: Colors.white,
                    onTap: _pickFromGallery,
                  ),
                ],
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _CornerOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _CornerPainter());
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    const d = 28.0;   // corner arm length
    const hPad = 72.0; // horizontal inset — narrows the frame
    const vPadTop = 100.0; // top inset — clears the top bar
    const vPadBottom = 160.0; // bottom inset — clears the button row
    final corners = [
      // top-left
      [const Offset(hPad, vPadTop + d), const Offset(hPad, vPadTop), const Offset(hPad + d, vPadTop)],
      // top-right
      [Offset(size.width - hPad - d, vPadTop), Offset(size.width - hPad, vPadTop), Offset(size.width - hPad, vPadTop + d)],
      // bottom-left
      [Offset(hPad, size.height - vPadBottom - d), Offset(hPad, size.height - vPadBottom), Offset(hPad + d, size.height - vPadBottom)],
      // bottom-right
      [Offset(size.width - hPad - d, size.height - vPadBottom), Offset(size.width - hPad, size.height - vPadBottom), Offset(size.width - hPad, size.height - vPadBottom - d)],
    ];
    for (final pts in corners) {
      final path = Path()
        ..moveTo(pts[0].dx, pts[0].dy)
        ..lineTo(pts[1].dx, pts[1].dy)
        ..lineTo(pts[2].dx, pts[2].dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ControlBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black38,
            border: Border.all(color: color.withOpacity(0.6)),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
