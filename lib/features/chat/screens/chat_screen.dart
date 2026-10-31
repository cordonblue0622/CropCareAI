import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/utils/label_formatter.dart';
import '../../../data/remote/ai_backend_service.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../data/models/chat_session_model.dart';
import '../../../data/models/diagnosis_model.dart';
import '../../../services/connectivity_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../crops/providers/crops_provider.dart';
import '../providers/chat_provider.dart';
import '../../../services/text_to_speech_service.dart';
import '../widgets/audio_message_player.dart';
import '../widgets/video_player_view.dart';

class ChatScreen extends StatefulWidget {
  final String? initialQuery;
  final bool hideInitialPromptText;
  final DiagnosisModel? initialDiagnosis;
  final Uint8List? initialImageBytes;
  final bool startFreshSession;
  final bool initialIsVideoFrame;
  final String? initialVideoPath;
  final String? cropId;
  final String? cropName;

  /// Guides GPT + Supabase when TFLite did not attach a diagnosis (eggplant / pechay).
  final String? hintCropType;

  const ChatScreen({
    super.key,
    this.initialQuery,
    this.hideInitialPromptText = false,
    this.initialDiagnosis,
    this.initialImageBytes,
    this.startFreshSession = false,
    this.initialIsVideoFrame = false,
    this.initialVideoPath,
    this.cropId,
    this.cropName,
    this.hintCropType,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  AuthProvider? _authProvider;
  bool _initializationStarted = false;
  bool _initializationComplete = false;
  bool _sending = false;
  String? _sendErrorMessage;
  Future<void> Function()? _retryFailedSend;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (!identical(_authProvider, auth)) {
      _authProvider?.removeListener(_handleAuthChanged);
      _authProvider = auth;
      auth.addListener(_handleAuthChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleAuthChanged());
  }

  void _handleAuthChanged() {
    if (!mounted || _initializationStarted) return;
    final auth = _authProvider;
    if (auth == null) return;

    if (auth.currentUser != null) {
      _initializationStarted = true;
      setState(() {});
      unawaited(_initializeConversation());
      return;
    }

    if (auth.status == AuthStatus.unauthenticated) {
      setState(() {
        _initializationComplete = true;
        _sendErrorMessage =
            'Your session has ended. Sign in again to analyze this photo.';
      });
    }
  }

  Future<void> _initializeConversation() async {
    try {
      await _init();
    } catch (error, stackTrace) {
      debugPrint('Conversation initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _sendErrorMessage =
              'Conversation could not start. Check your connection and retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _initializationComplete = true);
      }
    }
  }

  Future<void> _init() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) {
      throw StateError('Authentication resolved without a current user.');
    }
    final chat = context.read<ChatProvider>();
    var loadedExistingSession = false;
    if (widget.startFreshSession) {
      await chat.startNewSession(user.id, cropId: widget.cropId);
    } else if ((widget.initialDiagnosis?.chatSessionId ?? '').isNotEmpty) {
      await chat.fetchSessions(user.id);
      final diagnosisSessionId = widget.initialDiagnosis!.chatSessionId!;
      final diagnosisSession = chat.sessions
          .where((session) =>
              session.id == diagnosisSessionId && !session.isDeleted)
          .cast<ChatSessionModel?>()
          .firstOrNull;
      if (diagnosisSession != null) {
        await chat.loadSession(diagnosisSession);
        loadedExistingSession = true;
      } else {
        await chat.startNewSession(user.id, cropId: widget.cropId);
      }
    } else if (widget.cropId != null) {
      await chat.fetchSessions(user.id);
      // Load latest session for this crop if one exists
      final existing = chat.sessions
          .where((s) => s.cropId == widget.cropId && !s.isDeleted)
          .toList()
        ..sort((a, b) {
          final diagnosisTime = widget.initialDiagnosis?.diagnosedAt;
          if (diagnosisTime != null) {
            final aDistance =
                (a.createdAt.difference(diagnosisTime).inMilliseconds).abs();
            final bDistance =
                (b.createdAt.difference(diagnosisTime).inMilliseconds).abs();
            return aDistance.compareTo(bDistance);
          }
          return (b.lastMessageAt ?? b.createdAt)
              .compareTo(a.lastMessageAt ?? a.createdAt);
        });
      if (existing.isNotEmpty) {
        await chat.loadSession(existing.first);
        loadedExistingSession = true;
      } else {
        await chat.startNewSession(user.id, cropId: widget.cropId);
      }
    } else if (chat.currentSession == null) {
      await chat.startNewSession(user.id, cropId: widget.cropId);
    }
    if (loadedExistingSession) {
      return;
    }
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      await _sendMessage(
        widget.initialQuery!,
        hideMessageTextInUi: widget.hideInitialPromptText,
        attachedDiagnosis: widget.initialDiagnosis,
        attachedImageBytes: widget.initialImageBytes,
        isVideoFrame: widget.initialIsVideoFrame,
        attachedVideoPath: widget.initialVideoPath,
      );
    } else if (widget.initialDiagnosis != null ||
        widget.initialImageBytes != null) {
      final diagnosis = widget.initialDiagnosis;
      final confidenceText = diagnosis?.confidenceScore != null
          ? ' at ${(diagnosis!.confidenceScore! * 100).toStringAsFixed(0)}% confidence'
          : '';
      await _sendMessage(
        diagnosis != null
            ? 'The TFLite scanner produced a preliminary result$confidenceText. Independently identify the crop and condition from the attached photo; the scanner result may be wrong. If the image shows a different supported crop or condition, use the image-verified result and give its appropriate treatment plan.'
            : 'Please analyze this crop photo and tell me what to do next.',
        hideMessageTextInUi: true,
        attachedDiagnosis: widget.initialDiagnosis,
        attachedImageBytes: widget.initialImageBytes,
        isVideoFrame: widget.initialIsVideoFrame,
        attachedVideoPath: widget.initialVideoPath,
      );
    }
  }

  static CropType? _tryCropTypeFromLabel(String? labelKey) {
    final key = (labelKey ?? '').toLowerCase();
    if (key.contains('tomato')) return CropType.tomato;
    if (key.contains('eggplant') || key.contains('talong')) {
      return CropType.eggplant;
    }
    if (key.contains('pepper') || key.contains('capsicum')) {
      return CropType.pepper;
    }
    if (key.contains('pechay') ||
        key.contains('bok choy') ||
        key.contains('bokchoy')) {
      return CropType.pechay;
    }
    if (key.contains('squash') || key.contains('kalabasa')) {
      return CropType.squash;
    }
    return null;
  }

  /// Resolves the crop context sent to the AI backend.
  /// A farmer's explicit correction supersedes an earlier scanner hint.
  String? _effectiveHintCropType({String? latestUserMessage}) {
    final correctedCrop = _tryCropTypeFromLabel(latestUserMessage);
    if (correctedCrop != null) return correctedCrop.value;

    final w = (widget.hintCropType ?? '').trim().toLowerCase();
    if (w.isNotEmpty) return w;

    final linkedCropId =
        widget.cropId ?? context.read<ChatProvider>().currentSession?.cropId;
    if (linkedCropId != null && linkedCropId.isNotEmpty) {
      for (final crop in context.read<CropsProvider>().crops) {
        if (crop.id == linkedCropId && !crop.isDeleted) {
          return crop.cropType.value;
        }
      }
    }

    return null;
  }

  Future<bool> _sendMessage(
    String text, {
    bool hideMessageTextInUi = false,
    DiagnosisModel? attachedDiagnosis,
    List<int>? attachedImageBytes,
    List<List<int>> attachedImageBytesList = const [],
    String? attachedAudioPath,
    String? attachedVideoPath,
    bool isVideoFrame = false,
  }) async {
    if (_sending) return false;

    final trimmed = text.trim();
    final imageAttachments =
        attachedImageBytesList.where((bytes) => bytes.isNotEmpty).toList();
    if (imageAttachments.isEmpty &&
        attachedImageBytes != null &&
        attachedImageBytes.isNotEmpty) {
      imageAttachments.add(attachedImageBytes);
    }
    final hasImage = imageAttachments.isNotEmpty;
    final hasAudio =
        attachedAudioPath != null && attachedAudioPath.trim().isNotEmpty;
    if (trimmed.isEmpty && !hasImage && !hasAudio) return false;
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return false;

    final shouldHideMessageText =
        hideMessageTextInUi || (trimmed.isEmpty && (hasImage || hasAudio));

    final content = trimmed.isNotEmpty
        ? trimmed
        : 'I\'ve attached a crop photo. Please analyze it and tell me what you observe — any diseases, pests, or conditions — and what I should do.';

    setState(() {
      _sending = true;
      _sendErrorMessage = null;
      _retryFailedSend = null;
    });

    try {
      await context.read<ChatProvider>().sendMessage(
            userId: user.id,
            content: content,
            hideMessageTextInUi: shouldHideMessageText,
            attachedDiagnosis: attachedDiagnosis,
            attachedImageBytes:
                imageAttachments.isEmpty ? null : imageAttachments.first,
            attachedImageBytesList: imageAttachments,
            attachedAudioPath: attachedAudioPath,
            attachedVideoPath: attachedVideoPath,
            isVideoFrame: isVideoFrame,
            hintCropType: _effectiveHintCropType(latestUserMessage: content),
          );
      if (mounted) {
        _scrollToBottom();
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendErrorMessage =
              'Message could not be sent. Check your connection and retry.';
          _retryFailedSend = () => _sendMessage(
                content,
                hideMessageTextInUi: shouldHideMessageText,
                attachedDiagnosis: attachedDiagnosis,
                attachedImageBytes:
                    imageAttachments.isEmpty ? null : imageAttachments.first,
                attachedImageBytesList: imageAttachments,
                attachedAudioPath: attachedAudioPath,
                attachedVideoPath: attachedVideoPath,
                isVideoFrame: isVideoFrame,
              );
        });
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startNewChat() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    await context.read<ChatProvider>().startNewSession(user.id);
    setState(() {});
  }

  Future<void> _showConversationHistory() async {
    final chat = context.read<ChatProvider>();
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;

    // Refresh session list in the background – show the sheet immediately
    // with cached sessions so the user does not wait.
    unawaited(chat.fetchSessions(user.id));
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConversationHistorySheet(
        sessions: chat.sessions,
        currentSessionId: chat.currentSession?.id,
        onNewChat: () async {
          Navigator.pop(context);
          await _startNewChat();
        },
        onSelectSession: (session) async {
          Navigator.pop(context);
          await chat.loadSession(session);
          setState(() {});
          _scrollToBottom();
        },
      ),
    );
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_handleAuthChanged);
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final messages = chat.currentMessages;
    final hasOnlineVisionReview = messages.any((message) {
      if (message.role != MessageRole.assistant) return false;
      final sources = message.metadata?['sources'];
      final reviewedDisease =
          (message.metadata?['disease_name'] as String? ?? '').trim();
      return sources is List &&
          sources.contains('openai-vision') &&
          reviewedDisease.isNotEmpty &&
          message.metadata?['in_app_crop_scope'] == true;
    });
    final hasInitialScanContext = widget.initialDiagnosis != null ||
        widget.initialImageBytes?.isNotEmpty == true ||
        widget.initialIsVideoFrame ||
        (widget.initialVideoPath?.isNotEmpty ?? false);
    final waitingForInitialResponse = messages.isEmpty &&
        (chat.isLoading ||
            chat.isTyping ||
            _sending ||
            (hasInitialScanContext && !_initializationComplete));

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                widget.cropName != null
                    ? '${widget.cropName} — AI Chat'
                    : 'CropCare AI',
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            Text(
                widget.cropName != null
                    ? 'Crop-specific advice'
                    : 'Vegetable Doctor',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Conversation history',
            onPressed: () => _showConversationHistory(),
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New chat',
            onPressed: () => _startNewChat(),
          ),
        ],
      ),
      body: Column(children: [
        // Messages
        Expanded(
          child: waitingForInitialResponse
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: 12),
                      Text(
                        'Preparing your crop analysis...',
                        style: TextStyle(color: AppColors.textGray),
                      ),
                    ],
                  ),
                )
              : messages.isEmpty
                  ? _WelcomeView(
                      onSuggest: (s) => _sendMessage(s),
                    )
                  : ListView(
                      controller: _scrollCtrl,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        // _ScanImageCard removed — the image is already shown
                        // as a bubble inside the first user message.
                        if (widget.initialDiagnosis != null &&
                            !hasOnlineVisionReview)
                          _DiagnosisSummaryCard(
                              diagnosis: widget.initialDiagnosis!),
                        ...messages
                            .map((message) => _MessageBubble(message: message)),
                        if (chat.isTyping) const _TypingIndicator(),
                      ],
                    ),
        ),

        if (_sendErrorMessage != null)
          _SendErrorBanner(
            message: _sendErrorMessage!,
            onRetry: _sending ? null : _retryFailedSend,
            onDismiss: () => setState(() {
              _sendErrorMessage = null;
              _retryFailedSend = null;
            }),
          ),

        // Input bar
        _InputBar(
          controller: _textCtrl,
          sending: _sending,
          onSend: (text, imageBytesList) =>
              _sendMessage(text, attachedImageBytesList: imageBytesList),
          onSendWithVoice: (text, audioPath) => _sendMessage(
            text,
            hideMessageTextInUi: true,
            attachedAudioPath: audioPath,
          ),
        ),
      ]),
    );
  }
}

class _SendErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback onDismiss;

  const _SendErrorBanner({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFC62828), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF8E1B1B), fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
          IconButton(
            onPressed: onDismiss,
            tooltip: 'Dismiss error',
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _DiagnosisSummaryCard extends StatelessWidget {
  final DiagnosisModel diagnosis;

  const _DiagnosisSummaryCard({required this.diagnosis});

  String _modelLabel(String name, String? version) {
    final normalized = name.trim();
    final lower = normalized.toLowerCase();
    if (lower.contains('tflite') ||
        lower.contains('efficientnet') ||
        lower.contains('local')) {
      return 'TFLite';
    }
    final fullName = [normalized, version?.trim()]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .join(' ');
    return fullName;
  }

  @override
  Widget build(BuildContext context) {
    final confidence = diagnosis.confidenceScore != null
        ? '${(diagnosis.confidenceScore! * 100).toStringAsFixed(0)}% match'
        : 'Scan ready';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.backgroundGreenLight,
                ),
                child:
                    const Icon(Icons.eco, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  diagnosis.diagnosisMode == DiagnosisMode.offline
                      ? 'TFLite scan suggestion'
                      : 'AI diagnosis',
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.backgroundGreenLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  confidence,
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            humanizeDiseaseLabel(diagnosis.diseaseName),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          if (diagnosis.summary != null &&
              diagnosis.summary!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              diagnosis.summary!,
              style: const TextStyle(
                color: AppColors.textGray,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DiagnosisChip(
                icon: Icons.flag_outlined,
                label: diagnosis.severity.name.toUpperCase(),
              ),
              if (diagnosis.resultLabel != null &&
                  diagnosis.resultLabel!.isNotEmpty)
                _DiagnosisChip(
                  icon: Icons.label_outline,
                  label: diagnosis.resultLabel!,
                ),
              if (diagnosis.modelName != null &&
                  diagnosis.modelName!.isNotEmpty)
                _DiagnosisChip(
                  icon: Icons.memory,
                  label: _modelLabel(
                    diagnosis.modelName!,
                    diagnosis.modelVersion,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiagnosisChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DiagnosisChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.76,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.backgroundCream,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.primaryDark),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Welcome View ─────────────────────────────────────────────────────────

class _WelcomeView extends StatelessWidget {
  final void Function(String) onSuggest;
  const _WelcomeView({required this.onSuggest});

  static const _suggestions = [
    'What causes tomato blight?',
    'How to treat leaf curl disease?',
    'Signs of nitrogen deficiency',
    'Prevention for powdery mildew',
    'Best fungicide for eggplant',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.primaryDark, AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.eco, color: Colors.white, size: 38),
          ),
          const SizedBox(height: 16),
          const Text('Vegetable Doctor',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark)),
          const SizedBox(height: 8),
          const Text(
            'Ask about crop diseases, treatments, and care tips. I use real data from our disease knowledge base.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: AppColors.textGray, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 28),
          const Text('Try asking:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _suggestions
                .map((s) => ActionChip(
                      label: Text(s,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.primary)),
                      backgroundColor: AppColors.backgroundGreenLight,
                      side: BorderSide.none,
                      onPressed: () => onSuggest(s),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Message Bubble ───────────────────────────────────────────────────────

class _MessageBubble extends StatefulWidget {
  final ChatMessageModel message;
  const _MessageBubble({required this.message});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  // Local checklist state for treatment recommendations
  final Set<int> _checkedSteps = {};

  CropType? _resolveCropTypeForCard({
    required String rawCropType,
    required String labelKey,
    required String summary,
    required String diseaseName,
    required String cropName,
  }) {
    final candidates = [
      rawCropType,
      labelKey,
      summary,
      diseaseName,
      cropName,
    ];

    for (final candidate in candidates) {
      final resolved = _ChatScreenState._tryCropTypeFromLabel(candidate);
      if (resolved != null) {
        return resolved;
      }
    }

    final linkedCropId = context.read<ChatProvider>().currentSession?.cropId;
    if (linkedCropId != null && linkedCropId.isNotEmpty) {
      for (final crop in context.read<CropsProvider>().crops) {
        if (crop.id == linkedCropId && !crop.isDeleted) {
          return crop.cropType;
        }
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;

    // ── System action card: "Add to My Crops" suggestion ──
    if (message.role == MessageRole.system) {
      final meta = message.metadata ?? {};
      if (meta['type'] == 'add_crop_suggestion') {
        return _buildAddCropCard(context, meta);
      }
      return const SizedBox.shrink();
    }

    final isUser = message.role == MessageRole.user;
    final imageBytesList =
        message.imageBytesList?.where((bytes) => bytes.isNotEmpty).toList() ??
            (message.imageBytes != null && message.imageBytes!.isNotEmpty
                ? [message.imageBytes!]
                : const <Uint8List>[]);
    final hasImage = imageBytesList.isNotEmpty;
    final hideText = message.metadata?['hide_text'] == true;
    final audioPath = message.metadata?['audio_path'] as String?;
    final videoUrl = message.metadata?['video_url'] as String?;
    final posterUrl = message.metadata?['video_poster_url'] as String?;

    // Recommended actions for assistant messages
    final rawActions = message.metadata?['recommended_actions'];
    final List<String> actions = rawActions is List
        ? List<String>.from(rawActions.map((e) => e.toString()))
        : [];
    final showTreatmentCard = message.metadata?['show_treatment_card'] == true;
    final planTitle = (message.metadata?['plan_title'] as String?)?.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryDark,
              ),
              child: const Icon(Icons.eco, color: Colors.white, size: 18),
            ),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // ── Video bubble ──
                if (videoUrl != null)
                  videoUrl.startsWith('expired:')
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            if (posterUrl != null)
                              _renderPoster(posterUrl)
                            else
                              Container(
                                width: 220,
                                height: 150,
                                color: Colors.black26,
                              ),
                            Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(10),
                              child: const Icon(
                                Icons.error_outline,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Video expired',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                        )
                      : SizedBox(
                          width: 260,
                          child: VideoPlayerView(
                            videoSource: videoUrl,
                            inline: true,
                            autoplay: false,
                            showDeleteAction: false,
                          ),
                        ),
                // ── Image bubble (above text, like Messenger) ──
                if (hasImage)
                  Container(
                    width: imageBytesList.length == 1
                        ? 200
                        : MediaQuery.of(context).size.width * 0.72,
                    height: 200,
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72,
                    ),
                    margin: EdgeInsets.only(
                      bottom: message.content.isEmpty || hideText ? 0 : 4,
                    ),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: imageBytesList.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, index) => GestureDetector(
                        onTap: () => _showFullImage(
                          context,
                          imageBytesList[index],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.memory(
                            imageBytesList[index],
                            width: 200,
                            height: 200,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (audioPath != null && audioPath.trim().isNotEmpty) ...[
                  if (hasImage) const SizedBox(height: 8),
                  AudioMessagePlayer(
                    audioPath: audioPath,
                    isUser: isUser,
                  ),
                  const SizedBox(height: 6),
                ],
                // ── Text bubble ──
                if (!hideText && message.content.isNotEmpty)
                  Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(hasImage ? 4 : 16),
                        topRight: Radius.circular(hasImage ? 4 : 16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2))
                      ],
                    ),
                    child: Text(
                      message.content,
                      style: TextStyle(
                        color: isUser ? Colors.white : AppColors.textDark,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  )
                else if (!hasImage && !hideText)
                  Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2))
                      ],
                    ),
                    child: Text(
                      message.content,
                      style: TextStyle(
                        color: isUser ? Colors.white : AppColors.textDark,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                // ── Treatment checklist (assistant messages only) ──
                if (!isUser && showTreatmentCard && actions.isNotEmpty)
                  _buildTreatmentChecklist(
                    context,
                    actions,
                    title: planTitle?.isNotEmpty == true
                        ? planTitle!
                        : 'Treatment Steps',
                  ),
                if (!isUser && message.content.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 2),
                    child: ValueListenableBuilder<String?>(
                      valueListenable:
                          TextToSpeechService.instance.activeTextListenable,
                      builder: (_, __, ___) {
                        final isSpeaking = TextToSpeechService.instance
                            .isSpeakingText(message.content);
                        return InkWell(
                          onTap: () => isSpeaking
                              ? TextToSpeechService.instance.stop()
                              : TextToSpeechService.instance
                                  .speak(message.content),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Icon(
                              isSpeaking
                                  ? Icons.stop_circle_outlined
                                  : Icons.volume_up_outlined,
                              size: 18,
                              color: isSpeaking
                                  ? Colors.redAccent
                                  : AppColors.primary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildAddCropCard(BuildContext context, Map<String, dynamic> meta) {
    final alreadyLinked =
        context.watch<ChatProvider>().currentSession?.cropId?.isNotEmpty ==
            true;
    final diseaseName = meta['disease_name'] as String? ?? '';
    final labelKey = meta['label_key'] as String? ?? '';
    final rawSeverity = meta['severity'] as String? ?? '';
    final rawDiagnosisMode =
        meta['diagnosis_mode'] as String? ?? DiagnosisMode.online.value;
    final rawCropType = meta['crop_type'] as String? ?? '';
    final summary = meta['summary'] as String? ?? '';
    final modelName = meta['model_name'] as String? ?? '';
    final modelVersion = meta['model_version'] as String?;
    final confidenceScore = (meta['confidence_score'] as num?)?.toDouble();
    final resultLabel = meta['result_label'] as String?;
    final rawDetectedRegions = meta['detected_regions_json'];
    final detectedRegionsJson = rawDetectedRegions is Map
        ? Map<String, dynamic>.from(rawDetectedRegions)
        : null;
    final videoUrl = meta['video_url'] as String?;
    final imageUrl = (meta['image_url'] as String?)?.trim();
    final rawActions = meta['recommended_actions'];
    final List<String> steps = rawActions is List
        ? List<String>.from(rawActions.map((e) => e.toString()))
        : [];
    final diagnosisMode = DiagnosisMode.values.firstWhere(
      (mode) => mode.value == rawDiagnosisMode,
      orElse: () => DiagnosisMode.online,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 4),
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withOpacity(0.35)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_circle_outline,
                      color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Add to My Crops for Monitoring',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.primaryDark)),
                ),
              ],
            ),
            if (diseaseName.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Detected: ${humanizeDiseaseLabel(diseaseName)}',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.textGray)),
            ] else ...[
              const SizedBox(height: 6),
              const Text('Track this crop and follow the treatment plan above.',
                  style: TextStyle(fontSize: 12, color: AppColors.textGray)),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      alreadyLinked ? Colors.grey.shade400 : AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: Icon(
                  alreadyLinked ? Icons.check_circle : Icons.eco,
                  size: 16,
                ),
                label: Text(
                  alreadyLinked ? 'Already Added' : 'Add to My Crops',
                  style: const TextStyle(fontSize: 13),
                ),
                onPressed: alreadyLinked
                    ? null
                    : () {
                        final inferredCropType = _resolveCropTypeForCard(
                          rawCropType: rawCropType,
                          labelKey: labelKey,
                          summary: summary,
                          diseaseName: diseaseName,
                          cropName: '',
                        );
                        final cropNameCtrl = TextEditingController(
                          text: rawCropType.isNotEmpty
                              ? rawCropType.capitalize()
                              : inferredCropType != null
                                  ? inferredCropType.name.capitalize()
                                  : labelKey.isNotEmpty
                                      ? labelKey.split('_').first.capitalize()
                                      : diseaseName.split(' ').first,
                        );
                        _showAddCropFromCardDialog(context,
                            diseaseName: diseaseName,
                            labelKey: labelKey,
                            rawSeverity: rawSeverity,
                            diagnosisMode: diagnosisMode,
                            rawCropType: rawCropType,
                            summary: summary,
                            modelName: modelName,
                            modelVersion: modelVersion,
                            confidenceScore: confidenceScore,
                            resultLabel: resultLabel,
                            detectedRegionsJson: detectedRegionsJson,
                            videoUrl: videoUrl,
                            imageUrl: imageUrl,
                            steps: steps,
                            cropNameCtrl: cropNameCtrl);
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCropFromCardDialog(
    BuildContext context, {
    required String diseaseName,
    required String labelKey,
    required String rawSeverity,
    required DiagnosisMode diagnosisMode,
    required String rawCropType,
    required String summary,
    required String modelName,
    required String? modelVersion,
    required double? confidenceScore,
    required String? resultLabel,
    required Map<String, dynamic>? detectedRegionsJson,
    required String? videoUrl,
    required String? imageUrl,
    required List<String> steps,
    required TextEditingController cropNameCtrl,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        String? errorText;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Name Your Crop',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            content: TextField(
              controller: cropNameCtrl,
              autofocus: true,
              onChanged: (_) {
                if (errorText == null) {
                  return;
                }
                setDialogState(() => errorText = null);
              },
              decoration: InputDecoration(
                labelText: 'Crop Name',
                hintText: 'e.g. My Tomato Plant',
                errorText: errorText,
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () async {
                  final user = context.read<AuthProvider>().currentUser;
                  if (user == null) return;
                  if (context
                          .read<ChatProvider>()
                          .currentSession
                          ?.cropId
                          ?.isNotEmpty ==
                      true) {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('This diagnosis is already in My Crops.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  final severity = Severity.values.firstWhere(
                      (s) => s.value == rawSeverity,
                      orElse: () => Severity.moderate);
                  final cropsProvider = context.read<CropsProvider>();
                  final proposedName = cropNameCtrl.text.trim().isNotEmpty
                      ? cropNameCtrl.text.trim()
                      : rawCropType.isNotEmpty
                          ? rawCropType
                          : labelKey.isNotEmpty
                              ? labelKey.split('_').first
                              : 'My Crop';
                  final validationError = cropsProvider.validateUniqueCropName(
                    cropName: proposedName,
                  );
                  if (validationError != null) {
                    setDialogState(() => errorText = validationError);
                    return;
                  }

                  final resolvedCropType = _resolveCropTypeForCard(
                    rawCropType: rawCropType,
                    labelKey: labelKey,
                    summary: summary,
                    diseaseName: diseaseName,
                    cropName: proposedName,
                  );
                  if (resolvedCropType == null) {
                    setDialogState(
                      () => errorText =
                          'Please include the crop type in the name, for example "Pechay Bed 1".',
                    );
                    return;
                  }

                  Navigator.of(ctx).pop();
                  final cropId = await cropsProvider.addCropFromDiagnosis(
                    userId: user.id,
                    diseaseName: diseaseName,
                    labelKey: labelKey,
                    cropName: proposedName,
                    cropType: resolvedCropType,
                    severity: severity,
                    treatmentSteps: steps,
                    initialSummary: summary,
                    modelName: modelName,
                    modelVersion: modelVersion,
                    confidenceScore: confidenceScore,
                    resultLabel: resultLabel,
                    detectedRegionsJson: detectedRegionsJson,
                    videoUrl: videoUrl,
                    imageUrl: imageUrl?.isEmpty == true ? null : imageUrl,
                    diagnosisMode: diagnosisMode,
                    chatSessionId:
                        context.read<ChatProvider>().currentSession?.id,
                  );
                  if (!mounted) return;
                  if (cropId != null) {
                    await context
                        .read<ChatProvider>()
                        .linkCurrentSessionToCrop(cropId);
                    final syncWarning = cropsProvider.error;
                    final messenger = ScaffoldMessenger.of(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          syncWarning ??
                              'Crop added to My Crops and synced to your account.',
                        ),
                        backgroundColor:
                            syncWarning == null ? AppColors.primary : null,
                        duration: syncWarning == null
                            ? const Duration(seconds: 4)
                            : const Duration(seconds: 8),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        action: syncWarning == null
                            ? null
                            : SnackBarAction(
                                label: 'Retry',
                                onPressed: () async {
                                  final synced =
                                      await cropsProvider.retryCropSync(cropId);
                                  if (!messenger.mounted) return;
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        synced
                                            ? 'Crop synced to your account.'
                                            : 'Crop is still saved only on this device. Keep the app installed and try again later.',
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          cropsProvider.error ??
                              'Could not add this crop right now. Please try again.',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTreatmentChecklist(
    BuildContext context,
    List<String> actions, {
    required String title,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist_rounded,
                  color: AppColors.primary, size: 16),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: AppColors.primaryDark)),
              const Spacer(),
              Text(
                '${_checkedSteps.length}/${actions.length} done',
                style: const TextStyle(fontSize: 11, color: AppColors.textGray),
              ),
            ],
          ),
          const Divider(height: 10, thickness: 0.5),
          ...actions.asMap().entries.map((entry) {
            final idx = entry.key;
            final step = entry.value;
            final checked = _checkedSteps.contains(idx);
            return InkWell(
              onTap: () => setState(() {
                if (checked) {
                  _checkedSteps.remove(idx);
                } else {
                  _checkedSteps.add(idx);
                }
              }),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(top: 1, right: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: checked ? AppColors.primary : Colors.transparent,
                        border: Border.all(
                          color:
                              checked ? AppColors.primary : Colors.grey[400]!,
                          width: 1.5,
                        ),
                      ),
                      child: checked
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 13)
                          : null,
                    ),
                    Expanded(
                      child: Text(
                        step,
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              checked ? Colors.grey[400] : AppColors.textDark,
                          decoration: checked
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (_checkedSteps.length == actions.length && actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.celebration, color: AppColors.primary, size: 14),
                  SizedBox(width: 6),
                  Text('All tasks checked! Track in My Crops.',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _renderPoster(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(url, width: 200, height: 140, fit: BoxFit.cover);
    }
    return Image.file(File(url), width: 200, height: 140, fit: BoxFit.cover);
  }

  void _showFullImage(BuildContext context, Uint8List bytes) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

// ─── Typing Indicator ─────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.4, end: 1).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.only(right: 8),
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: AppColors.primaryDark),
          child: const Icon(Icons.eco, color: Colors.white, size: 18),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            ...List.generate(
              3,
              (i) => AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => Container(
                  margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(
                        i == 0 ? _fade.value : (i == 1 ? 0.6 : 0.3)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─── Conversation History Sheet ───────────────────────────────────────────

class _ConversationHistorySheet extends StatelessWidget {
  final List<ChatSessionModel> sessions;
  final String? currentSessionId;
  final VoidCallback onNewChat;
  final void Function(ChatSessionModel) onSelectSession;

  const _ConversationHistorySheet({
    required this.sessions,
    required this.currentSessionId,
    required this.onNewChat,
    required this.onSelectSession,
  });

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final visibleSessions = sessions.where((s) => !s.isDeleted).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
              child: Row(
                children: [
                  const Text(
                    'Conversations',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onNewChat,
                    icon: const Icon(Icons.add,
                        size: 18, color: AppColors.primary),
                    label: const Text('New chat',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700)),
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.backgroundGreenLight,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Session list
            Expanded(
              child: visibleSessions.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No previous conversations yet.\nStart a new chat to begin.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.textGray, fontSize: 14),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollCtrl,
                      itemCount: visibleSessions.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 68),
                      itemBuilder: (_, i) {
                        final s = visibleSessions[i];
                        final isCurrent = s.id == currentSessionId;
                        final date = s.lastMessageAt ?? s.createdAt;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 6),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isCurrent
                                  ? AppColors.primary
                                  : AppColors.backgroundGreenLight,
                            ),
                            child: Icon(
                              Icons.chat_bubble_outline_rounded,
                              color:
                                  isCurrent ? Colors.white : AppColors.primary,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            s.title ?? 'Chat ${_formatDate(date)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  isCurrent ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 14,
                              color: AppColors.textDark,
                            ),
                          ),
                          subtitle: Text(
                            _formatDate(date),
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textLightGray),
                          ),
                          trailing: isCurrent
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.backgroundGreenLight,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text('Active',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700)),
                                )
                              : const Icon(Icons.chevron_right,
                                  color: AppColors.textLightGray),
                          onTap: () => onSelectSession(s),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Input Bar ────────────────────────────────────────────────────────────

class _InputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool sending;
  final Future<bool> Function(String text, List<Uint8List> imageBytesList)
      onSend;
  final Future<bool> Function(String text, String audioPath) onSendWithVoice;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onSendWithVoice,
  });

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> with WidgetsBindingObserver {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isListening = false;
  bool _startingMic = false;
  bool _transcribing = false;
  bool _usingBackendFallback = false;
  final List<Uint8List> _pendingImageBytesList = [];
  Future<String?>? _stopOperation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        (_isListening || _usingBackendFallback)) {
      unawaited(_stopRecordingForLifecycle());
    }
  }

  Future<String?> _stopRecorder() {
    return _stopOperation ??= _recorder.stop().whenComplete(() {
      _stopOperation = null;
    });
  }

  Future<void> _stopRecordingForLifecycle() async {
    try {
      await _stopRecorder();
    } catch (error, stackTrace) {
      debugPrint(
        '[ChatInput] Could not stop recording after app lifecycle change: '
        '$error\n$stackTrace',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isListening = false;
          _usingBackendFallback = false;
        });
      }
    }
  }

  Future<void> _disposeRecorder() async {
    if (_isListening || _usingBackendFallback) {
      try {
        await _stopRecorder();
      } catch (error, stackTrace) {
        debugPrint(
          '[ChatInput] Could not stop recorder during disposal: '
          '$error\n$stackTrace',
        );
      }
    }
    await _recorder.dispose();
  }

  Future<bool> _ensureMicrophonePermission() async {
    final currentStatus = await Permission.microphone.status;
    if (currentStatus.isGranted) {
      return true;
    }

    final requestedStatus = await Permission.microphone.request();
    return requestedStatus.isGranted;
  }

  Future<void> _toggleMic() async {
    if (_startingMic || _transcribing) return;

    if (_isListening || _usingBackendFallback) {
      await _stopRecordingAndTranscribe();
      return;
    }

    if (!await _ensureMicrophonePermission()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Microphone permission is required to use voice input.'),
        ),
      );
      return;
    }

    _startingMic = true;
    try {
      var isOnline = true;
      try {
        isOnline = await context.read<ConnectivityService>().isConnected;
      } catch (_) {}

      if (!isOnline) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice messages require an internet connection.'),
          ),
        );
        return;
      }

      if (!mounted) return;
      final backendFallbackStarted = await _startBackendRecordingFallback();
      if (!backendFallbackStarted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not start online voice recording.'),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isListening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone is busy. Please try again.')),
      );
    } finally {
      _startingMic = false;
    }
  }

  Future<bool> _startBackendRecordingFallback() async {
    try {
      final hasRecorderPermission = await _recorder.hasPermission();
      if (!hasRecorderPermission) {
        return false;
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

      if (!mounted) {
        return true;
      }

      setState(() {
        _isListening = true;
        _usingBackendFallback = true;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> _buildRecordingPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final voiceDir = Directory(path.join(docsDir.path, 'voice_messages'));
    if (!await voiceDir.exists()) {
      await voiceDir.create(recursive: true);
    }
    return path.join(
      voiceDir.path,
      'chat-mic-${DateTime.now().millisecondsSinceEpoch}.wav',
    );
  }

  Future<void> _stopRecordingAndTranscribe() async {
    String? recordingPath;
    try {
      recordingPath = await _stopRecorder();
    } catch (_) {
      // Ignore stop errors — UI state must still be reset so the mic indicator turns off.
    }
    if (!mounted) return;

    setState(() {
      _isListening = false;
      _transcribing = true;
      _usingBackendFallback = false;
    });

    if (recordingPath == null || recordingPath.trim().isEmpty) {
      if (!mounted) return;
      setState(() => _transcribing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No audio was captured. Try again.')),
      );
      return;
    }

    try {
      final audioBytes = await File(recordingPath).readAsBytes();
      final transcriptResponse =
          await context.read<AiBackendService>().transcribeAudio(
                audioBytes: audioBytes,
                filename: path.basename(recordingPath),
              );
      final transcript = transcriptResponse.transcript.trim();

      if (!mounted) return;
      setState(() => _transcribing = false);

      if (transcript.isNotEmpty) {
        await widget.onSendWithVoice(transcript, recordingPath);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No speech was detected. Try again.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _transcribing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Voice transcription failed. Check the backend connection and try again.'),
        ),
      );
    }
  }

  Future<void> _showImageSourceSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.backgroundGreenLight,
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: AppColors.primary),
                ),
                title: const Text('Take a photo',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Open live camera'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.backgroundGreenLight,
                  ),
                  child: const Icon(Icons.photo_library_rounded,
                      color: AppColors.primary),
                ),
                title: const Text('Upload from gallery',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Pick an existing photo'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;

    if (choice == 'camera') {
      // Use the in-app camera (works on web via getUserMedia, and on native)
      final bytes = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(builder: (_) => const _ChatCameraScreen()),
      );
      if (bytes != null && mounted) {
        setState(() => _pendingImageBytesList.add(bytes));
      }
    } else {
      // Gallery via image_picker
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage(imageQuality: 85);
      if (picked.isEmpty) return;
      final bytesList =
          await Future.wait(picked.map((image) => image.readAsBytes()));
      if (mounted) {
        setState(() {
          _pendingImageBytesList.addAll(bytesList.map(Uint8List.fromList));
        });
      }
    }
  }

  Future<void> _submit() async {
    if (widget.sending) return;
    if (_isListening || _usingBackendFallback) {
      await _stopRecordingAndTranscribe();
      return;
    }

    final text = widget.controller.text;
    final imageBytesList = List<Uint8List>.from(_pendingImageBytesList);
    if (text.trim().isEmpty && imageBytesList.isEmpty) return;

    widget.controller.clear();
    setState(_pendingImageBytesList.clear);
    final sent = await widget.onSend(text, imageBytesList);
    if (!sent &&
        mounted &&
        widget.controller.text.trim().isEmpty &&
        _pendingImageBytesList.isEmpty) {
      widget.controller.text = text;
      setState(() => _pendingImageBytesList.addAll(imageBytesList));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeRecorder());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, -2))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_pendingImageBytesList.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 46, bottom: 8),
                child: SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _pendingImageBytesList.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            _pendingImageBytesList[index],
                            width: 76,
                            height: 76,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: -8,
                          right: -8,
                          child: Material(
                            color: Colors.black87,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => setState(
                                () => _pendingImageBytesList.removeAt(index),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            Row(children: [
              _IconBtn(
                icon: Icons.camera_alt_outlined,
                color: AppColors.textGray,
                onTap: _showImageSourceSheet,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: _isListening
                        ? 'Listening...'
                        : 'Ask about crop diseases...',
                    hintStyle: TextStyle(
                      color: _isListening
                          ? AppColors.primary
                          : AppColors.textLightGray,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: _isListening
                        ? AppColors.backgroundGreenLight
                        : AppColors.backgroundCream,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _IconBtn(
                icon: _isListening ? Icons.stop_circle : Icons.mic_none_rounded,
                color: _isListening ? Colors.red : AppColors.textGray,
                onTap: _toggleMic,
              ),
              const SizedBox(width: 6),
              widget.sending
                  ? const SizedBox.square(
                      dimension: 40,
                      child: Center(
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    )
                  : GestureDetector(
                      onTap: _submit,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                        child: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _IconBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
            shape: BoxShape.circle, color: AppColors.backgroundCream),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

// ─── In-App Camera Screen ─────────────────────────────────────────────────
// Pops with Uint8List when a photo is captured, or null when cancelled.

class _ChatCameraScreen extends StatefulWidget {
  const _ChatCameraScreen();

  @override
  State<_ChatCameraScreen> createState() => _ChatCameraScreenState();
}

class _ChatCameraScreenState extends State<_ChatCameraScreen> {
  CameraController? _ctrl;
  bool _ready = false;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      _ctrl = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _ctrl!.initialize();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera unavailable: $e');
    }
  }

  bool _popped = false;

  Future<void> _capture() async {
    if (_ctrl == null || !_ctrl!.value.isInitialized || _capturing || _popped) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final file = await _ctrl!.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted && !_popped) {
        _popped = true;
        Navigator.of(context).pop(Uint8List.fromList(bytes));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _capturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not capture the photo. Please try again.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Preview ──
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              )
            else if (!_ready)
              const Center(
                  child: CircularProgressIndicator(color: Colors.white))
            else
              CameraPreview(_ctrl!),

            // ── Top bar ──
            Positioned(
              top: 12,
              left: 12,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),

            // ── Capture button ──
            if (_ready)
              Positioned(
                bottom: 36,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _capturing ? null : _capture,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: _capturing
                          ? const Padding(
                              padding: EdgeInsets.all(18),
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 3),
                            )
                          : Container(
                              margin: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- String Extensions --------------------------------------------------
extension _StringCapitalize on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
