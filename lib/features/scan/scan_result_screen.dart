import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/utils/image_reference.dart';
import '../../../data/models/crop_model.dart';
import '../../../data/models/diagnosis_model.dart';
import '../../../data/models/disease_knowledge_model.dart';
import '../../../data/remote/ai_backend_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/local_classifier_service.dart';
import '../../../services/video_diagnosis_service.dart';
import '../../../core/utils/label_formatter.dart';
import '../auth/providers/auth_provider.dart';
import '../crops/providers/crops_provider.dart';
import '../home/home_screen.dart';
import '../chat/screens/chat_screen.dart';

class ScanResultScreen extends StatefulWidget {
  final XFile imageFile;
  final String? cropId;
  final CropType? cropTypeHint;
  final Uint8List? imageBytes;
  final String? initialQuery;
  final bool openChatOnComplete;
  final bool isFromVideo;
  final XFile? videoFile;

  const ScanResultScreen({
    super.key,
    required this.imageFile,
    this.cropId,
    this.cropTypeHint,
    this.imageBytes,
    this.initialQuery,
    this.openChatOnComplete = false,
    this.isFromVideo = false,
    this.videoFile,
  });

  @override
  State<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends State<ScanResultScreen> {
  bool _analyzing = true;
  DiseaseKnowledgeModel? _match;
  AiBackendDetectResponse? _detection;
  String? _analysisMessage;
  bool _saving = false;
  bool _tracked = false;
  bool _redirectingToChat = false;
  bool _analysisFailed = false;
  Uint8List? _resolvedImageBytes;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    final cropsProvider = context.read<CropsProvider>();
    final aiBackend = context.read<AiBackendService>();
    final connectivity = context.read<ConnectivityService>();
    final localClassifier = context.read<LocalClassifierService>();
    try {
      if (cropsProvider.diseaseKnowledge.isEmpty) {
        await cropsProvider.fetchDiseaseKnowledge();
      }

      final selectedCropType = _resolveSelectedCropType(cropsProvider);
      final stillImageBytes = widget.imageBytes ??
          (widget.isFromVideo ? null : await widget.imageFile.readAsBytes());
      _resolvedImageBytes = stillImageBytes;

      AiBackendDetectResponse detection;
      if (widget.isFromVideo && widget.videoFile != null) {
        Uint8List? posterBytes = stillImageBytes;
        try {
          final videoResult =
              await VideoDiagnosisService(localClassifier: localClassifier)
                  .analyzeVideo(
                      videoFilePath: widget.videoFile!.path,
                      cropTypeHint: selectedCropType?.value);
          posterBytes ??= videoResult.posterBytes;
          if (videoResult.bestDetection != null) {
            detection = videoResult.bestDetection!;
          } else if (posterBytes != null && posterBytes.isNotEmpty) {
            detection = await aiBackend.detectImage(
              imageBytes: posterBytes,
              filename: 'video_frame.jpg',
              cropType: selectedCropType?.value,
            );
          } else {
            throw VideoDiagnosisException(
              'Could not extract a usable frame from the recorded video.',
            );
          }
          // Use the best frame as the visible poster image.
          if (posterBytes != null) {
            _resolvedImageBytes = posterBytes;
          }
        } catch (_) {
          posterBytes ??=
              await _extractVideoPosterBytes(widget.videoFile!.path);
          if (posterBytes == null || posterBytes.isEmpty) {
            throw Exception(
              'AI backend unavailable right now. Please analyze a clearer video or capture a still photo instead.',
            );
          }
          _resolvedImageBytes = posterBytes;
          // Video pipeline failed entirely — fall back to remote on poster bytes.
          detection = await aiBackend.detectImage(
            imageBytes: posterBytes,
            filename: 'video_frame.jpg',
            cropType: selectedCropType?.value,
          );
        }
      } else {
        final imageBytes = stillImageBytes;
        if (imageBytes == null || imageBytes.isEmpty) {
          throw Exception('No scan image was available for analysis.');
        }
        detection = await _detectStillImage(
          aiBackend: aiBackend,
          connectivity: connectivity,
          localClassifier: localClassifier,
          imageBytes: imageBytes,
          selectedCropType: selectedCropType,
        );
      }

      final rejectionMessage = _rejectionMessageForDetection(
        detection: detection,
        selectedCropType: selectedCropType,
      );
      final match = _resolveDiseaseMatch(
        detection: detection,
        cropsProvider: cropsProvider,
        selectedCropType: selectedCropType,
        rejectionMessage: rejectionMessage,
      );
      final infoMessage = rejectionMessage ??
          (match == null
              ? 'We could not confidently identify a supported crop disease from this photo. Upload a clearer close-up of the affected leaf and try again.'
              : detection.source.toLowerCase().contains('local')
                  ? 'Analyzed on device using ${detection.model.name} ${detection.model.version}.'
                  : 'Analyzed using ${detection.model.name} ${detection.model.version} via the CropCare AI backend.');
      final analysisMessage = infoMessage;
      final diagnosis = match != null && _shouldAttachDiagnosisToChat(detection)
          ? _matchToDiagnosis(
              match,
              detection: detection,
              analysisMessage: analysisMessage,
            )
          : null;

      // Store detection data directly — avoids an unnecessary rebuild when
      // we are about to navigate away to chat (prevents the result-screen
      // flash / glitch the user sees before the conversation opens).
      _detection = detection;
      _match = match;
      _analysisMessage = analysisMessage;

      if (!mounted) return;

      if (widget.openChatOnComplete) {
        // Navigate to chat without first showing the result screen.
        await _openChat(diagnosis: diagnosis);
        return;
      }

      setState(() {
        _analysisFailed = false;
        _analyzing = false;
      });
    } catch (error) {
      if (!mounted) return;
      // If we're supposed to go straight to chat, still do that even on error.
      // The backend being down should not block the user from reaching the AI chat.
      if (widget.openChatOnComplete) {
        _analysisMessage =
            'The crop scanner could not reach the AI backend. Please analyze the image directly and tell me what crop disease or condition you can see, and what I should do.';
        await _openChat(diagnosis: null);
        return;
      }
      setState(() {
        _analysisMessage =
            'AI backend unavailable right now. You can still ask the assistant for general guidance.';
        _analysisFailed = true;
        _analyzing = false;
      });
    }
  }

  Future<void> _retryAnalysis() async {
    if (_analyzing) return;
    setState(() {
      _analyzing = true;
      _analysisFailed = false;
      _analysisMessage = null;
      _match = null;
      _detection = null;
    });
    await _analyze();
  }

  Future<Uint8List?> _extractVideoPosterBytes(String videoPath) async {
    try {
      return await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        timeMs: 0,
        quality: 85,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _openChat({DiagnosisModel? diagnosis}) async {
    if (!widget.openChatOnComplete || _redirectingToChat || !mounted) {
      return;
    }

    final normalizedInitialQuery = widget.initialQuery?.trim();
    String? initialQuery;
    var hideInitialPromptText = false;

    if (normalizedInitialQuery != null && normalizedInitialQuery.isNotEmpty) {
      initialQuery = normalizedInitialQuery;
    } else if (diagnosis == null) {
      initialQuery = _buildUncertainScanPrompt();
      hideInitialPromptText = true;
    }
    // else: diagnosis != null with no custom query — ChatScreen builds its own prompt

    final cropsProvider = context.read<CropsProvider>();
    final hintCropType = _resolveChatHintCropType(
      selectedCropType: _resolveSelectedCropType(cropsProvider),
      diagnosis: diagnosis,
    );

    setState(() => _redirectingToChat = true);

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          startFreshSession: true,
          cropId: diagnosis?.cropId,
          initialQuery: initialQuery,
          hideInitialPromptText: hideInitialPromptText,
          initialDiagnosis: diagnosis,
          initialImageBytes: _resolvedImageBytes ?? widget.imageBytes,
          initialIsVideoFrame: widget.isFromVideo,
          initialVideoPath: widget.isFromVideo ? widget.videoFile?.path : null,
          hintCropType: hintCropType,
        ),
      ),
    );
  }

  Future<void> _trackDiagnosis() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null || _match == null) return;
    final cropId = widget.cropId ??
        (context.read<CropsProvider>().activeCrops.isNotEmpty
            ? context.read<CropsProvider>().activeCrops.first.id
            : null);
    if (cropId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No crop selected to link diagnosis.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final imageUrl =
          _resolvedImageBytes != null && _resolvedImageBytes!.isNotEmpty
              ? buildInlineImageDataUrl(_resolvedImageBytes!)
              : null;
      final diagnosis = DiagnosisModel(
        id: const Uuid().v4(),
        cropId: cropId,
        userId: user.id,
        diagnosisMode: _diagnosisModeFor(_detection),
        labelKey: _primaryDetection?.labelKey ?? _match?.labelKey,
        diseaseName: _match!.diseaseName,
        confidenceScore: _primaryDetection?.confidence,
        severity: _inferSeverityForDetection(
          knowledge: _match,
          detection: _detection,
        ),
        imageUrl: imageUrl,
        resultLabel: _primaryDetection?.label,
        summary: _match!.description ?? _analysisMessage,
        detectedRegionsJson: _detection?.toDetectedRegionsJson(),
        modelName: _detection?.model.name,
        modelVersion: _detection?.model.version,
        videoUrl: widget.videoFile?.path,
        diagnosedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      await context.read<CropsProvider>().saveDiagnosis(diagnosis);
      if (mounted) setState(() => _tracked = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Could not save this diagnosis. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewBytes = _resolvedImageBytes ?? widget.imageBytes;

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      bottomNavigationBar: const AppPushedScreenBottomNav(currentIndex: 2),
      body: SafeArea(
        child: Column(children: [
          // Header
          Container(
            color: AppColors.primaryDark,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CropCare AI',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17)),
                  Text('Diagnostic Result',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                ],
              ),
            ]),
          ),

          if (_analyzing)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text('Analyzing image...',
                        style:
                            TextStyle(color: AppColors.textGray, fontSize: 15)),
                    SizedBox(height: 6),
                    Text('Consulting disease knowledge base',
                        style: TextStyle(
                            color: AppColors.textLightGray, fontSize: 13)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Captured image thumb
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: previewBytes != null && previewBytes.isNotEmpty
                          ? Image.memory(
                              previewBytes,
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          : widget.isFromVideo
                              ? Container(
                                  height: 180,
                                  width: double.infinity,
                                  color: AppColors.backgroundGreenLight,
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.all(20),
                                  child: const Text(
                                    'No video preview frame was available for this result.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.textGray,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : _XFileImageView(
                                  widget.imageFile,
                                  height: 180,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                    ),
                    const SizedBox(height: 20),

                    if (_analysisMessage != null) ...[
                      _analysisBanner(_analysisMessage!),
                      const SizedBox(height: 16),
                    ],

                    if (_match == null)
                      _noMatchCard()
                    else
                      _resultCard(_match!),

                    if (_analysisFailed) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _retryAnalysis,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primary),
                          foregroundColor: AppColors.primary,
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try Scan Again'),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Action buttons — track only when there's a match
                    if (_match != null) ...[
                      if (_tracked)
                        _successBanner()
                      else
                        ElevatedButton.icon(
                          onPressed: _saving ? null : _trackDiagnosis,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.track_changes),
                          label: Text(_saving ? 'Saving...' : 'Yes, track it',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                      const SizedBox(height: 12),
                    ],

                    // Ask AI — always visible so GPT can analyze even unclear photos
                    OutlinedButton.icon(
                      onPressed: () {
                        final crops = context.read<CropsProvider>();
                        final hint =
                            _resolveSelectedCrop(crops)?.cropType.value;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              startFreshSession: true,
                              initialDiagnosis: _match != null
                                  ? _matchToDiagnosis(_match!)
                                  : null,
                              initialImageBytes: _resolvedImageBytes,
                              initialQuery: _match == null
                                  ? _buildUncertainScanPrompt()
                                  : null,
                              hintCropType: hint,
                            ),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.primary),
                        foregroundColor: AppColors.primary,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: Text(
                          _match == null
                              ? 'Ask AI to analyze this photo'
                              : 'Ask AI for more info',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _resultCard(DiseaseKnowledgeModel kb) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.biotech, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          const Text('DIAGNOSIS RESULT',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textGray,
                  letterSpacing: 1)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Text(_confidenceLabel,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange)),
          ),
        ]),
        const SizedBox(height: 14),
        Text(humanizeDiseaseLabel(kb.diseaseName),
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark)),
        if (kb.scientificName != null)
          Text(kb.scientificName!,
              style: const TextStyle(
                  color: AppColors.textGray,
                  fontStyle: FontStyle.italic,
                  fontSize: 14)),
        if (kb.description != null) ...[
          const SizedBox(height: 10),
          Text(kb.description!,
              style: const TextStyle(
                  color: AppColors.textGray, fontSize: 13, height: 1.4)),
        ],
        if (kb.symptoms != null && kb.symptoms!.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 10),
          const Text('Symptoms Detected',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          ...kb.symptoms!.take(4).map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.circle,
                          size: 7, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(s,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textGray,
                                  height: 1.4))),
                    ]),
              )),
        ],
        if (kb.treatmentSteps != null && kb.treatmentSteps!.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 10),
          const Text('Recommended Treatment',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          ...kb.treatmentSteps!.take(3).toList().asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.backgroundGreenLight),
                          child: Center(
                            child: Text('${e.key + 1}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(e.value,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textGray,
                                    height: 1.4))),
                      ]),
                ),
              ),
        ],
        if (kb.estimatedRecoveryDays != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.backgroundGreenLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.schedule, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('Est. recovery: ${kb.estimatedRecoveryDays} days',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ]),
          ),
        ],
        if (_detection != null) ...[
          const SizedBox(height: 12),
          Text(
            'Backend source: ${_detection!.model.name} ${_detection!.model.version}',
            style: const TextStyle(
              color: AppColors.textLightGray,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ]),
    );
  }

  Widget _analysisBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundGreenLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noMatchCard() {
    final topGuess = _primaryDetection;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        const Icon(Icons.help_outline,
            size: 48, color: AppColors.textLightGray),
        const SizedBox(height: 12),
        const Text('Unclear offline result',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
            'The offline model could not confidently confirm a supported diagnosis from this upload. Try a clearer close-up or go online for a stronger review.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textGray, fontSize: 13, height: 1.4)),
        if (topGuess != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.backgroundGreenLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Top offline guess',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  humanizeDiseaseLabel(topGuess.label),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(topGuess.confidence * 100).toStringAsFixed(0)}% confidence',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
        ],
      ]),
    );
  }

  Widget _successBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.backgroundGreenLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: const Row(children: [
        Icon(Icons.check_circle, color: AppColors.primary),
        SizedBox(width: 10),
        Expanded(
            child: Text('Diagnosis saved. Tracking recovery for this crop.',
                style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13))),
      ]),
    );
  }

  DiagnosisModel _matchToDiagnosis(
    DiseaseKnowledgeModel kb, {
    AiBackendDetectResponse? detection,
    String? analysisMessage,
  }) {
    final now = DateTime.now();
    final sourceDetection = detection ?? _detection;
    final primaryDetection = sourceDetection?.primaryDetection;
    return DiagnosisModel(
      id: const Uuid().v4(),
      cropId: widget.cropId ?? '',
      userId: context.read<AuthProvider>().currentUser?.id ?? '',
      diagnosisMode: _diagnosisModeFor(sourceDetection),
      labelKey: primaryDetection?.labelKey ?? kb.labelKey,
      diseaseName: kb.diseaseName,
      confidenceScore: primaryDetection?.confidence,
      severity: _inferSeverityForDetection(
        knowledge: kb,
        detection: sourceDetection,
      ),
      resultLabel: primaryDetection?.label,
      summary: kb.description ?? analysisMessage ?? _analysisMessage,
      detectedRegionsJson: sourceDetection?.toDetectedRegionsJson(),
      modelName: sourceDetection?.model.name,
      modelVersion: sourceDetection?.model.version,
      videoUrl: widget.videoFile?.path,
      diagnosedAt: now,
      createdAt: now,
      updatedAt: now,
    );
  }

  CropModel? _resolveSelectedCrop(CropsProvider cropsProvider) {
    if (widget.cropId != null && widget.cropId!.isNotEmpty) {
      for (final crop in cropsProvider.activeCrops) {
        if (crop.id == widget.cropId) {
          return crop;
        }
      }
    }
    return null;
  }

  String? _resolveChatHintCropType({
    required CropType? selectedCropType,
    required DiagnosisModel? diagnosis,
  }) {
    if (selectedCropType != null) {
      return selectedCropType.value;
    }
    return null;
  }

  /// User message when the on-device scan did not attach a confident diagnosis.
  String _buildUncertainScanPrompt() {
    final selectedCropType =
        _resolveSelectedCropType(context.read<CropsProvider>());
    final topGuess = _primaryDetection;
    final cropLabel = selectedCropType != null
        ? _cropTypeLabel(selectedCropType)
        : 'the selected crop';

    if (topGuess != null) {
      return 'The offline scan could not confidently confirm $cropLabel from the attached photo. '
          'Top offline guess: ${humanizeDiseaseLabel(topGuess.label)} at '
          '${(topGuess.confidence * 100).toStringAsFixed(0)}% confidence. '
          'Please analyze the image carefully, explain whether the top guess looks correct, '
          'and tell the farmer whether to retry with a clearer photo or continue online for better help.';
    }

    return 'The offline scan could not confidently confirm the attached crop image. '
        'Please analyze the image carefully, explain what you observe, and tell '
        'the farmer whether to retry with a clearer photo or continue online for better help.';
  }

  DiseaseKnowledgeModel? _resolveDiseaseMatch({
    required AiBackendDetectResponse detection,
    required CropsProvider cropsProvider,
    required CropType? selectedCropType,
    required String? rejectionMessage,
  }) {
    if (rejectionMessage != null) {
      return null;
    }

    final primary = detection.primaryDetection;
    if (primary == null) {
      return null;
    }

    final targetLabel = _normalizeLabel(primary.label);
    final targetLabelKey = primary.labelKey?.trim();
    final cropType = _preferredCropTypeForDetection(
      detection: detection,
      selectedCropType: selectedCropType,
    );

    for (final knowledge in cropsProvider.diseaseKnowledge) {
      final sameCrop = cropType == null || knowledge.cropType == cropType;
      if (!sameCrop) continue;

      final knowledgeLabelKey = knowledge.labelKey?.trim();
      if (targetLabelKey != null &&
          targetLabelKey.isNotEmpty &&
          knowledgeLabelKey != null &&
          knowledgeLabelKey.isNotEmpty &&
          knowledgeLabelKey == targetLabelKey) {
        return knowledge;
      }

      final diseaseName = _normalizeLabel(knowledge.diseaseName);
      if (diseaseName == targetLabel ||
          diseaseName.contains(targetLabel) ||
          targetLabel.contains(diseaseName)) {
        return knowledge;
      }
    }

    return _buildFallbackKnowledge(
      label: primary.label,
      cropType: cropType,
      detection: detection,
    );
  }

  String? _rejectionMessageForDetection({
    required AiBackendDetectResponse detection,
    required CropType? selectedCropType,
  }) {
    final primary = detection.primaryDetection;
    final topGuess = primary == null
        ? null
        : '${humanizeDiseaseLabel(primary.label)} '
            '(${(primary.confidence * 100).toStringAsFixed(0)}% confidence)';
    final safetyNotes = detection.notes
        .where((note) =>
            note.startsWith('Possible crop-family mismatch:') ||
            note.startsWith('The model has '))
        .join(' ');

    if (detection.status.toLowerCase() == 'no_match') {
      if (selectedCropType != null && topGuess != null) {
        return 'I can\'t confidently confirm your selected ${_cropTypeLabel(selectedCropType)} crop offline from this photo. '
            'Top offline guess: $topGuess. ${safetyNotes.isEmpty ? '' : '$safetyNotes '}'
            'Upload a clearer close-up or go online for better assistance.';
      }
      if (topGuess != null) {
        return 'I can\'t confidently confirm a supported crop diagnosis offline from this photo. '
            'Top offline guess: $topGuess. ${safetyNotes.isEmpty ? '' : '$safetyNotes '}'
            'Upload a clearer close-up or go online for better assistance.';
      }
      if (safetyNotes.isNotEmpty) {
        return '$safetyNotes Upload a clearer close-up or go online for better assistance.';
      }
      return detection.notes.isNotEmpty
          ? detection.notes.first
          : 'This photo does not clearly match a supported crop disease. Upload a clear crop-leaf photo and try again.';
    }

    if (primary == null) {
      return 'This photo does not clearly match a supported crop disease. Upload a clear crop-leaf photo and try again.';
    }

    final isLocalDetection = detection.source.toLowerCase().contains('local');
    final confidence = primary.confidence;
    final minimumConfidence = selectedCropType != null
        ? AppConstants.temporaryScannerHintedAcceptedConfidence
        : AppConstants.temporaryScannerAcceptedConfidence;
    if (isLocalDetection && confidence < minimumConfidence) {
      return selectedCropType != null
          ? 'I can\'t confidently confirm your selected ${_cropTypeLabel(selectedCropType)} crop offline from this photo. ${topGuess != null ? 'Top offline guess: $topGuess. ' : ''}Upload a clearer close-up or go online for better assistance.'
          : 'I can\'t confidently confirm a supported crop diagnosis offline from this photo. ${topGuess != null ? 'Top offline guess: $topGuess. ' : ''}Upload a clearer close-up or go online for better assistance.';
    }

    final predictedCropType = _tryParseCropType(detection.cropType);
    if (selectedCropType != null &&
        predictedCropType != null &&
        predictedCropType != selectedCropType) {
      return 'I can\'t confidently confirm your selected ${_cropTypeLabel(selectedCropType)} crop from this photo. '
          'Top ${isLocalDetection ? 'offline ' : ''}guess: ${topGuess ?? _cropTypeLabel(predictedCropType)}. '
          'Upload a photo of the selected crop or go online for better assistance.';
    }

    return null;
  }

  CropType? _tryParseCropType(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    for (final cropType in CropType.values) {
      if (cropType.value == value.trim()) {
        return cropType;
      }
    }
    return null;
  }

  CropType? _resolveSelectedCropType(CropsProvider cropsProvider) {
    final selectedCrop = _resolveSelectedCrop(cropsProvider);
    if (selectedCrop != null) {
      return selectedCrop.cropType;
    }

    if (widget.cropTypeHint != null) {
      return widget.cropTypeHint;
    }

    return _inferCropTypeFromPrompt(widget.initialQuery);
  }

  Future<AiBackendDetectResponse> _detectStillImage({
    required AiBackendService aiBackend,
    required ConnectivityService connectivity,
    required LocalClassifierService localClassifier,
    required Uint8List imageBytes,
    required CropType? selectedCropType,
  }) async {
    final cropType = selectedCropType?.value;
    final isConnected = await connectivity.isConnected;

    if (isConnected) {
      try {
        return await aiBackend.detectImage(
          imageBytes: imageBytes,
          filename: widget.imageFile.name,
          cropType: cropType,
        );
      } catch (_) {
        return localClassifier.classifyImage(
          imageBytes: imageBytes,
          filename: widget.imageFile.name,
          cropType: cropType,
        );
      }
    }

    return localClassifier.classifyImage(
      imageBytes: imageBytes,
      filename: widget.imageFile.name,
      cropType: cropType,
    );
  }

  CropType? _preferredCropTypeForDetection({
    required AiBackendDetectResponse detection,
    required CropType? selectedCropType,
  }) {
    if (detection.source.toLowerCase().contains('local') &&
        selectedCropType != null) {
      return selectedCropType;
    }

    return _tryParseCropType(detection.cropType) ?? selectedCropType;
  }

  CropType? _inferCropTypeFromPrompt(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.contains('pepper') || normalized.contains('capsicum')) {
      return CropType.pepper;
    }
    if (normalized.contains('pechay') ||
        normalized.contains('bok choy') ||
        normalized.contains('bokchoy')) {
      return CropType.pechay;
    }
    if (normalized.contains('eggplant') || normalized.contains('talong')) {
      return CropType.eggplant;
    }
    if (normalized.contains('squash') || normalized.contains('kalabasa')) {
      return CropType.squash;
    }
    if (normalized.contains('tomato') || normalized.contains('kamatis')) {
      return CropType.tomato;
    }

    return null;
  }

  bool _shouldAttachDiagnosisToChat(AiBackendDetectResponse detection) {
    final source = detection.source.toLowerCase();
    final modelName = detection.model.name.toLowerCase();
    final label = detection.primaryDetection?.label.toLowerCase() ?? '';
    final selectedCropType =
        _resolveSelectedCropType(context.read<CropsProvider>());
    final predictedCropType = _tryParseCropType(detection.cropType);

    if (selectedCropType != null &&
        predictedCropType != null &&
        predictedCropType != selectedCropType) {
      return false;
    }

    return detection.status.toLowerCase() == 'ok' &&
        detection.primaryDetection != null &&
        !source.contains('mock') &&
        !modelName.contains('mock') &&
        label != 'sample_disease_region';
  }

  DiagnosisMode _diagnosisModeFor(AiBackendDetectResponse? detection) {
    final source = detection?.source.toLowerCase() ?? '';
    if (source.contains('local')) {
      return DiagnosisMode.offline;
    }
    return DiagnosisMode.online;
  }

  Severity _inferSeverityForDetection({
    required DiseaseKnowledgeModel? knowledge,
    required AiBackendDetectResponse? detection,
  }) {
    final labelKey =
        (detection?.primaryDetection?.labelKey ?? knowledge?.labelKey ?? '')
            .toLowerCase();
    final label =
        (detection?.primaryDetection?.label ?? knowledge?.diseaseName ?? '')
            .toLowerCase();
    final fingerprint = '$labelKey $label';

    if (fingerprint.contains('healthy')) {
      return Severity.healthy;
    }

    if (RegExp(
      r'late blight|yellow leaf curl|mosaic|virus|wilt|small leaf|white mold',
    ).hasMatch(fingerprint)) {
      return Severity.severe;
    }

    if (RegExp(
      r'powdery mildew|leaf spot|early blight|bacterial spot|target spot|leaf mold|septoria|insect pest',
    ).hasMatch(fingerprint)) {
      return Severity.moderate;
    }

    final confidence = detection?.primaryDetection?.confidence ?? 0;
    if (confidence >= 0.85) {
      return Severity.mild;
    }

    return Severity.moderate;
  }

  DiseaseKnowledgeModel _buildFallbackKnowledge({
    required String label,
    required CropType? cropType,
    required AiBackendDetectResponse detection,
  }) {
    final now = DateTime.now();
    final humanized = humanizeDiseaseLabel(label);
    // Preserve the old `_titleCaseLabel` defensive fallback: if the input has
    // no alphanumerics (e.g. backend returned "@@@" or "---"), surface
    // "Unknown disease" rather than the raw symbols.
    final hasAlphanumeric = humanized.contains(RegExp(r'[a-zA-Z0-9]'));
    final title = hasAlphanumeric ? humanized : 'Unknown disease';
    return DiseaseKnowledgeModel(
      id: 'backend-$label',
      cropType: cropType ?? CropType.tomato,
      labelKey:
          detection.primaryDetection?.labelKey ?? _normalizeLabelKey(label),
      diseaseName: title,
      description:
          'Detected by the AI backend. Add a matching knowledge-base entry for tailored treatment details.',
      symptoms: const [
        'Backend detection returned a label for the affected plant area.',
        'A matching treatment record was not found in the current knowledge base.',
      ],
      treatmentSteps: const [
        'Inspect the highlighted affected area again.',
        'Use the AI assistant for monitoring guidance.',
        'Confirm the disease against your curated knowledge dataset.',
      ],
      sourceName: detection.source,
      createdAt: now,
      updatedAt: now,
    );
  }

  String _normalizeLabel(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  String _cropTypeLabel(CropType cropType) {
    final name = cropType.name;
    return '${name[0].toUpperCase()}${name.substring(1)}';
  }

  String _normalizeLabelKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  AiBackendDetectionItem? get _primaryDetection => _detection?.primaryDetection;

  String get _confidenceLabel {
    final confidence = _primaryDetection?.confidence;
    if (confidence == null) {
      return 'MATCH FOUND';
    }
    return '${(confidence * 100).toStringAsFixed(0)}% CONFIDENCE';
  }
}

class _XFileImageView extends StatelessWidget {
  final XFile file;
  final double? height;
  final double? width;
  final BoxFit fit;

  const _XFileImageView(
    this.file, {
    required this.height,
    required this.width,
    required this.fit,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            height: height,
            width: width,
            color: AppColors.backgroundGreenLight,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(color: AppColors.primary),
          );
        }

        return Image.memory(
          snapshot.data!,
          height: height,
          width: width,
          fit: fit,
          gaplessPlayback: true,
        );
      },
    );
  }
}
