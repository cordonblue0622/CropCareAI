import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_enums.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../data/models/chat_session_model.dart';
import '../../../data/models/diagnosis_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../crops/providers/crops_provider.dart';
import '../providers/chat_provider.dart';
import '../../home/home_screen.dart';

class ChatScreen extends StatefulWidget {
  final String? initialQuery;
  final DiagnosisModel? initialDiagnosis;
  final Uint8List? initialImageBytes;
  final bool startFreshSession;
  final bool initialIsVideoFrame;
  final String? cropId;
  final String? cropName;

  const ChatScreen({
    super.key,
    this.initialQuery,
    this.initialDiagnosis,
    this.initialImageBytes,
    this.startFreshSession = false,
    this.initialIsVideoFrame = false,
    this.cropId,
    this.cropName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;
  final bool _hasShownAddCropDialog = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final chat = context.read<ChatProvider>();
    if (widget.startFreshSession || chat.currentSession == null) {
      await chat.startNewSession(user.id, cropId: widget.cropId);
    } else if (widget.cropId != null &&
        chat.currentSession?.cropId != widget.cropId) {
      // Load latest session for this crop if one exists
      final existing = chat.sessions
          .where((s) => s.cropId == widget.cropId && !s.isDeleted)
          .toList()
        ..sort((a, b) => (b.lastMessageAt ?? b.createdAt)
            .compareTo(a.lastMessageAt ?? a.createdAt));
      if (existing.isNotEmpty) {
        await chat.loadSession(existing.first);
      } else {
        await chat.startNewSession(user.id, cropId: widget.cropId);
      }
    }
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      await _sendMessage(
        widget.initialQuery!,
        attachedDiagnosis: widget.initialDiagnosis,
        attachedImageBytes: widget.initialImageBytes,
        isVideoFrame: widget.initialIsVideoFrame,
      );
    } else if (widget.initialDiagnosis != null || widget.initialImageBytes != null) {
      await _sendMessage(
        widget.initialDiagnosis != null
            ? 'I just scanned a crop and got a diagnosis: ${widget.initialDiagnosis!.diseaseName}. What should I do?'
            : 'Please analyze this crop photo and tell me what to do next.',
        attachedDiagnosis: widget.initialDiagnosis,
        attachedImageBytes: widget.initialImageBytes,
        isVideoFrame: widget.initialIsVideoFrame,
      );
    }
  }

  void _showAddCropDialog(DiagnosisModel diagnosis) {
    final cropNameCtrl = TextEditingController(
        text: diagnosis.labelKey != null && diagnosis.labelKey!.isNotEmpty
            ? diagnosis.labelKey!.split('_').first.capitalize()
            : diagnosis.diseaseName.split(' ').first);
    // Get recommended actions from the latest assistant message metadata
    final chat = context.read<ChatProvider>();
    final actions = chat.currentMessages
        .where((m) => m.role == MessageRole.assistant)
        .lastOrNull
        ?.metadata?['recommended_actions'];
    final latestAssistant = chat.currentMessages.lastWhere(
      (m) => m.role == MessageRole.assistant,
      orElse: () => ChatMessageModel(
        id: '',
        sessionId: '',
        userId: '',
        role: MessageRole.assistant,
        content: diagnosis.summary ?? '',
        createdAt: DateTime.now(),
      ),
    );
    final List<String> steps =
        actions is List ? List<String>.from(actions.map((e) => e.toString())) : [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.eco, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Add to My Crops?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Track the health of this crop and follow its treatment plan.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Detected: ${diagnosis.diseaseName}',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: cropNameCtrl,
              decoration: InputDecoration(
                labelText: 'Crop Name',
                hintText: 'e.g. My Tomato Plant',
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Skip', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final user = context.read<AuthProvider>().currentUser;
              if (user == null) return;
              final cropsProvider = context.read<CropsProvider>();
              final cropId = await cropsProvider.addCropFromDiagnosis(
                    userId: user.id,
                    diseaseName: diagnosis.diseaseName,
                    labelKey: diagnosis.labelKey ?? '',
                    cropName: cropNameCtrl.text.trim().isNotEmpty
                        ? cropNameCtrl.text.trim()
                        : (diagnosis.labelKey?.split('_').first ?? ''),
                    cropType: _cropTypeFromLabel(diagnosis.labelKey),
                    severity: diagnosis.severity,
                    treatmentSteps: steps,
                    initialSummary: diagnosis.summary ?? latestAssistant.content,
                    confidenceScore: diagnosis.confidenceScore,
                    resultLabel: diagnosis.resultLabel,
                    modelName: diagnosis.modelName,
                    modelVersion: diagnosis.modelVersion,
                  );
              if (!mounted) return;
              if (cropId != null) {
                await context.read<ChatProvider>().linkCurrentSessionToCrop(cropId);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Crop added to My Crops!'),
                    backgroundColor: AppColors.primary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
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
            child: const Text('Add to My Crops'),
          ),
        ],
      ),
    );
    cropNameCtrl.dispose();
  }

  static CropType _cropTypeFromLabel(String? labelKey) {
    final key = (labelKey ?? '').toLowerCase();
    if (key.contains('tomato')) return CropType.tomato;
    if (key.contains('eggplant')) return CropType.eggplant;
    if (key.contains('pepper') || key.contains('capsicum')) {
      return CropType.pepper;
    }
    if (key.contains('pechay') || key.contains('bok choy') || key.contains('bokchoy')) {
      return CropType.pechay;
    }
    if (key.contains('squash') || key.contains('kalabasa')) {
      return CropType.squash;
    }
    return CropType.tomato; // default
  }

  Future<void> _sendMessage(
    String text, {
    DiagnosisModel? attachedDiagnosis,
    List<int>? attachedImageBytes,
    bool isVideoFrame = false,
  }) async {
    final trimmed = text.trim();
    final hasImage = attachedImageBytes != null && attachedImageBytes.isNotEmpty;
    if (trimmed.isEmpty && !hasImage) return;
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;

    final content = trimmed.isNotEmpty
        ? trimmed
        : 'I\'ve attached a crop photo. Please analyze it and tell me what you observe — any diseases, pests, or conditions — and what I should do.';

    _textCtrl.clear();
    setState(() => _sending = true);
    await context.read<ChatProvider>().sendMessage(
          userId: user.id,
          content: content,
          attachedDiagnosis: attachedDiagnosis,
          attachedImageBytes: attachedImageBytes,
          isVideoFrame: isVideoFrame,
        );
    setState(() => _sending = false);
    _scrollToBottom();
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

    // Refresh session list
    await chat.fetchSessions(user.id);
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
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final messages = chat.currentMessages;
    final hasInitialScanContext =
        widget.initialImageBytes != null || widget.initialDiagnosis != null;

    return Scaffold(
      backgroundColor: AppColors.backgroundCream,
      bottomNavigationBar: const AppPushedScreenBottomNav(currentIndex: -1),
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
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 17)),
            Text(
              widget.cropName != null
                  ? 'Crop-specific advice'
                  : 'Vegetable Doctor',
              style: const TextStyle(
                  fontSize: 12, color: Colors.white70)),
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
          child: chat.isLoading && messages.isEmpty && !hasInitialScanContext
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : messages.isEmpty && !hasInitialScanContext
                  ? _WelcomeView(
                      onSuggest: (s) => _sendMessage(s),
                    )
                  : ListView(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      children: [
                        // _ScanImageCard removed — the image is already shown
                        // as a bubble inside the first user message.
                        if (widget.initialDiagnosis != null)
                          _DiagnosisSummaryCard(diagnosis: widget.initialDiagnosis!),
                        ...messages.map((message) => _MessageBubble(message: message)),
                        if (chat.isTyping) const _TypingIndicator(),
                      ],
                    ),
        ),

        // Input bar
        _InputBar(
          controller: _textCtrl,
          sending: _sending,
          onSend: () => _sendMessage(_textCtrl.text),
          onSendWithImage: (bytes) => _sendMessage('', attachedImageBytes: bytes),
        ),
      ]),
    );
  }
}

class _ScanImageCard extends StatelessWidget {
  final Uint8List imageBytes;

  const _ScanImageCard({required this.imageBytes});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.68,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.memory(
              imageBytes,
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _DiagnosisSummaryCard extends StatelessWidget {
  final DiagnosisModel diagnosis;

  const _DiagnosisSummaryCard({required this.diagnosis});

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
                child: const Icon(Icons.eco, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'AI diagnosis',
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            diagnosis.diseaseName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          if (diagnosis.summary != null && diagnosis.summary!.trim().isNotEmpty) ...[
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
              if (diagnosis.resultLabel != null && diagnosis.resultLabel!.isNotEmpty)
                _DiagnosisChip(
                  icon: Icons.label_outline,
                  label: diagnosis.resultLabel!,
                ),
              if (diagnosis.modelName != null && diagnosis.modelName!.isNotEmpty)
                _DiagnosisChip(
                  icon: Icons.memory,
                  label: '${diagnosis.modelName} ${diagnosis.modelVersion ?? ''}'.trim(),
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
    return Container(
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
          Text(
            label,
            style: const TextStyle(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
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
            style: TextStyle(
                color: AppColors.textGray, fontSize: 14, height: 1.5),
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
    final hasImage = message.imageBytes != null && message.imageBytes!.isNotEmpty;

    // Recommended actions for assistant messages
    final rawActions = message.metadata?['recommended_actions'];
    final List<String> actions = rawActions is List
        ? List<String>.from(rawActions.map((e) => e.toString()))
        : [];

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
                // ── Image bubble (above text, like Messenger) ──
                if (hasImage)
                  GestureDetector(
                    onTap: () => _showFullImage(context, message.imageBytes!),
                    child: Stack(
                      children: [
                        Container(
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.72),
                          margin: EdgeInsets.only(
                              bottom: message.content.isEmpty ? 0 : 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(isUser ? 18 : 4),
                              bottomRight: Radius.circular(isUser ? 4 : 18),
                            ),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.10),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3))
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(isUser ? 18 : 4),
                              bottomRight: Radius.circular(isUser ? 4 : 18),
                            ),
                            child: Image.memory(
                              message.imageBytes!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: 200,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                        // Video frame badge
                        if (message.isVideoFrame)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.65),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.videocam,
                                      color: Colors.white, size: 12),
                                  SizedBox(width: 4),
                                  Text(
                                    'VIDEO',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                // ── Text bubble ──
                if (message.content.isNotEmpty &&
                    message.content !=
                        'I\'ve attached a crop photo. Please analyze it and tell me what you observe — any diseases, pests, or conditions — and what I should do.')
                  Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                else if (!hasImage)
                  Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                if (!isUser && actions.isNotEmpty)
                  _buildTreatmentChecklist(context, actions),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildAddCropCard(
      BuildContext context, Map<String, dynamic> meta) {
    final diseaseName = meta['disease_name'] as String? ?? '';
    final labelKey = meta['label_key'] as String? ?? '';
    final rawSeverity = meta['severity'] as String? ?? '';
    final rawCropType = meta['crop_type'] as String? ?? '';
    final summary = meta['summary'] as String? ?? '';
    final modelName = meta['model_name'] as String? ?? '';
    final rawActions = meta['recommended_actions'];
    final List<String> steps = rawActions is List
        ? List<String>.from(rawActions.map((e) => e.toString()))
        : [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 4),
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85),
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
              Text('Detected: $diseaseName',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textGray)),
            ] else ...[
              const SizedBox(height: 6),
              const Text('Track this crop and follow the treatment plan above.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textGray)),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: const Icon(Icons.eco, size: 16),
                label: const Text('Add to My Crops',
                    style: TextStyle(fontSize: 13)),
                onPressed: () {
                  final cropNameCtrl = TextEditingController(
                      text: labelKey.isNotEmpty
                          ? labelKey.split('_').first.capitalize()
                          : rawCropType.isNotEmpty
                              ? rawCropType.capitalize()
                              : diseaseName.split(' ').first);
                  _showAddCropFromCardDialog(context,
                      diseaseName: diseaseName,
                      labelKey: labelKey,
                      rawSeverity: rawSeverity,
                      rawCropType: rawCropType,
                      summary: summary,
                      modelName: modelName,
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
    required String rawCropType,
    required String summary,
    required String modelName,
    required List<String> steps,
    required TextEditingController cropNameCtrl,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Name Your Crop',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: cropNameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Crop Name',
            hintText: 'e.g. My Tomato Plant',
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
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final user = context.read<AuthProvider>().currentUser;
              if (user == null) return;
              final severity = Severity.values.firstWhere(
                  (s) => s.value == rawSeverity,
                  orElse: () => Severity.moderate);
              final cropsProvider = context.read<CropsProvider>();
              final cropId = await cropsProvider.addCropFromDiagnosis(
                    userId: user.id,
                    diseaseName: diseaseName,
                    labelKey: labelKey,
                    cropName: cropNameCtrl.text.trim().isNotEmpty
                        ? cropNameCtrl.text.trim()
                        : labelKey.isNotEmpty
                            ? labelKey.split('_').first
                            : rawCropType.isNotEmpty
                                ? rawCropType
                                : 'My Crop',
                    cropType: rawCropType.isNotEmpty
                        ? _ChatScreenState._cropTypeFromLabel(rawCropType)
                        : _ChatScreenState._cropTypeFromLabel(labelKey),
                    severity: severity,
                    treatmentSteps: steps,
                    initialSummary: summary,
                    modelName: modelName,
                  );
              if (!mounted) return;
              if (cropId != null) {
                await context.read<ChatProvider>().linkCurrentSessionToCrop(cropId);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Crop added to My Crops!'),
                    backgroundColor: AppColors.primary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
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
  }

  Widget _buildTreatmentChecklist(
      BuildContext context, List<String> actions) {
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
              const Text('Treatment Steps',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: AppColors.primaryDark)),
              const Spacer(),
              Text(
                '${_checkedSteps.length}/${actions.length} done',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textGray),
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
                        color: checked
                            ? AppColors.primary
                            : Colors.transparent,
                        border: Border.all(
                          color: checked
                              ? AppColors.primary
                              : Colors.grey[400]!,
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
                          color: checked
                              ? Colors.grey[400]
                              : AppColors.textDark,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.celebration,
                      color: AppColors.primary, size: 14),
                  SizedBox(width: 6),
                  Text('All steps checked! Track in My Crops.',
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(16)),
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
                    icon: const Icon(Icons.add, size: 18,
                        color: AppColors.primary),
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
                              color: isCurrent
                                  ? Colors.white
                                  : AppColors.primary,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            s.title ?? 'Chat ${_formatDate(date)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 14,
                              color: AppColors.textDark,
                            ),
                          ),
                          subtitle: Text(
                            _formatDate(date),
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textLightGray),
                          ),
                          trailing: isCurrent
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.backgroundGreenLight,
                                    borderRadius:
                                        BorderRadius.circular(12),
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
  final VoidCallback onSend;
  final void Function(List<int> imageBytes) onSendWithImage;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onSendWithImage,
  });

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _handledCurrentMicSession = false;
  bool _startingMic = false;

  @override
  void initState() {
    super.initState();
    _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _scheduleFinishMicSession();
        }
      },
      onError: (_) {
        if (!mounted) return;
        _handledCurrentMicSession = true;
        setState(() => _isListening = false);
      },
    ).then((ok) {
      if (mounted) setState(() => _speechAvailable = ok);
    });
  }

  void _scheduleFinishMicSession() {
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      _finishMicSession();
    });
  }

  void _finishMicSession() {
    if (!mounted || _handledCurrentMicSession) return;
    _handledCurrentMicSession = true;
    setState(() => _isListening = false);
    if (widget.controller.text.trim().isNotEmpty) {
      widget.onSend();
    }
  }

  Future<void> _toggleMic() async {
    if (_startingMic) return;

    if (_isListening || _speech.isListening) {
      await _speech.stop();
      _finishMicSession();
      return;
    }

    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone not available on this device.')),
      );
      return;
    }

    _startingMic = true;
    try {
      _handledCurrentMicSession = true;
      await _speech.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      if (!mounted) return;
      _handledCurrentMicSession = false;
      setState(() => _isListening = true);

      final didStart = await _speech.listen(
        onResult: (result) {
          if (mounted) {
            widget.controller.text = result.recognizedWords;
            widget.controller.selection = TextSelection.fromPosition(
              TextPosition(offset: widget.controller.text.length),
            );
          }
        },
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 8),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          autoPunctuation: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );

      if (!didStart && mounted) {
        setState(() => _isListening = false);
        _handledCurrentMicSession = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start microphone recognition.')),
        );
      }
    } catch (_) {
      _handledCurrentMicSession = true;
      if (!mounted) return;
      setState(() => _isListening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone is busy. Please try again.')),
      );
    } finally {
      _startingMic = false;
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
      if (bytes != null && mounted) widget.onSendWithImage(bytes);
    } else {
      // Gallery via image_picker
      final picker = ImagePicker();
      final picked =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      widget.onSendWithImage(bytes);
    }
  }

  @override
  void dispose() {
    _speech.cancel();
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
        child: Row(children: [
          // Camera / photo
          _IconBtn(
            icon: Icons.camera_alt_outlined,
            color: AppColors.textGray,
            onTap: _showImageSourceSheet,
          ),
          const SizedBox(width: 6),

          // Text field
          Expanded(
            child: TextField(
              controller: widget.controller,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (v) {
                if (v.trim().isNotEmpty && !widget.sending) widget.onSend();
              },
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Mic button
          _IconBtn(
            icon: _isListening ? Icons.stop_circle : Icons.mic_none_rounded,
            color: _isListening ? Colors.red : AppColors.textGray,
            onTap: _toggleMic,
          ),
          const SizedBox(width: 6),

          // Send button
          widget.sending
              ? const SizedBox.square(
                  dimension: 40,
                  child: Center(
                      child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                              color: AppColors.primary, strokeWidth: 2))))
              : GestureDetector(
                  onTap: widget.onSend,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: AppColors.primary),
                    child: const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
        ]),
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
    if (_ctrl == null || !_ctrl!.value.isInitialized || _capturing || _popped) return;
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
          SnackBar(content: Text('Could not capture photo: $e')),
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
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 22),
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
                        border:
                            Border.all(color: Colors.white, width: 4),
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
