import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_enums.dart';
import '../../../data/local/bundled_disease_knowledge.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../data/models/chat_session_model.dart';
import '../../../data/models/diagnosis_model.dart';
import '../../../data/remote/ai_backend_service.dart';
import '../../../data/models/disease_knowledge_model.dart';
import '../../../data/remote/supabase_service.dart';
import '../../../services/connectivity_service.dart';

class ChatProvider extends ChangeNotifier {
  static const Set<String> _supportedTreatmentCardCrops = {
    'tomato',
    'eggplant',
    'pepper',
    'pechay',
    'squash',
  };

  final SupabaseService _supabase;
  final DatabaseHelper _db;
  final AiBackendService _aiBackend;
  final ConnectivityService _connectivity;

  List<ChatSessionModel> _sessions = [];
  List<ChatMessageModel> _currentMessages = [];
  ChatSessionModel? _currentSession;
  List<DiseaseKnowledgeModel> _knowledgeBase = [];
  bool _isLoading = false;
  bool _isTyping = false;

  ChatProvider({
    required SupabaseService supabase,
    required DatabaseHelper db,
    required AiBackendService aiBackend,
    required ConnectivityService connectivity,
  })  : _supabase = supabase,
        _db = db,
        _aiBackend = aiBackend,
        _connectivity = connectivity;

  List<ChatSessionModel> get sessions => _sessions;
  List<ChatMessageModel> get currentMessages => _currentMessages;
  ChatSessionModel? get currentSession => _currentSession;
  bool get isLoading => _isLoading;
  bool get isTyping => _isTyping;

  // ─── Init ─────────────────────────────────────────────────────────────────

  Future<void> loadKnowledgeBase() async {
    try {
      final rows = await _supabase.getDiseaseKnowledge();
      if (rows.isNotEmpty) {
        _knowledgeBase = rows.map(DiseaseKnowledgeModel.fromMap).toList();
        await _db.upsertRows(
          AppConstants.diseaseKnowledgeTable,
          _knowledgeBase.map((knowledge) => knowledge.toMap()),
        );
        notifyListeners();
        return;
      }
    } catch (_) {}

    final cachedRows = await _db.queryDiseaseKnowledge('');
    if (cachedRows.isNotEmpty) {
      _knowledgeBase = cachedRows.map(DiseaseKnowledgeModel.fromMap).toList();
      notifyListeners();
      return;
    }

    final bundled = BundledDiseaseKnowledge.records();
    if (bundled.isNotEmpty) {
      _knowledgeBase = bundled;
      await _db.upsertRows(
        AppConstants.diseaseKnowledgeTable,
        bundled.map((knowledge) => knowledge.toMap()),
      );
    }

    notifyListeners();
  }

  Future<void> fetchSessions(String userId) async {
    try {
      final rows = await _supabase.getChatSessions(userId);
      _sessions = rows.map(ChatSessionModel.fromMap).toList();
      await _db.upsertRows(
        AppConstants.chatSessionsTable,
        _sessions.map((session) => session.toMap()),
      );
    } catch (_) {
      final rows =
          await _db.queryByUserId(AppConstants.chatSessionsTable, userId);
      _sessions = rows.map(ChatSessionModel.fromMap).toList();
    }
    notifyListeners();
  }

  // ─── Session Management ──────────────────────────────────────────────────

  Future<void> startNewSession(String userId, {String? cropId}) async {
    final now = DateTime.now();
    final session = ChatSessionModel(
      id: const Uuid().v4(),
      userId: userId,
      cropId: cropId,
      title: 'Chat ${now.day}/${now.month}/${now.year}',
      isOfflineSession: false,
      lastMessageAt: now,
      createdAt: now,
      updatedAt: now,
    );
    _currentSession = session;
    _currentMessages = [];

    try {
      await _supabase.upsertChatSession(_sessionRemoteMap(session));
    } catch (_) {}
    await _db.upsertRow(AppConstants.chatSessionsTable, session.toMap());

    _sessions.insert(0, session);
    notifyListeners();
  }

  Future<void> loadSession(ChatSessionModel session) async {
    _currentSession = session;
    _isLoading = true;
    notifyListeners();

    try {
      final rows = await _supabase.getChatMessages(session.id);
      _currentMessages = rows.map(ChatMessageModel.fromMap).toList();
      await _db.upsertRows(
        AppConstants.chatMessagesTable,
        _currentMessages.map((message) => message.toMap()),
      );
    } catch (_) {
      final rows = await _db.queryChatMessages(session.id);
      _currentMessages = rows.map(ChatMessageModel.fromMap).toList();
    }

    // Restore images from Supabase Storage URLs stored in metadata
    for (var i = 0; i < _currentMessages.length; i++) {
      final url = _currentMessages[i].imageUrl;
      if (url != null && url.isNotEmpty) {
        try {
          final res = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 15));
          if (res.statusCode == 200) {
            _currentMessages[i] =
                _currentMessages[i].copyWith(imageBytes: res.bodyBytes);
          }
        } catch (_) {}
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> linkCurrentSessionToCrop(String cropId) async {
    final current = _currentSession;
    if (current == null || cropId.isEmpty || current.cropId == cropId) {
      return;
    }

    final updated = current.copyWith(
      cropId: cropId,
      updatedAt: DateTime.now(),
    );
    _currentSession = updated;

    final idx = _sessions.indexWhere((s) => s.id == updated.id);
    if (idx != -1) {
      _sessions[idx] = updated;
    }

    try {
      await _supabase.upsertChatSession(_sessionRemoteMap(updated));
    } catch (_) {}

    await _db.upsertRow(AppConstants.chatSessionsTable, updated.toMap());
    notifyListeners();
  }

  // ─── Send Message ────────────────────────────────────────────────────────

  Future<void> sendMessage({
    required String userId,
    required String content,
    DiagnosisModel? attachedDiagnosis,
    List<int>? attachedImageBytes,
    String? attachedImageMimeType,
    bool isVideoFrame = false,
    String? hintCropType,
  }) async {
    if (_currentSession == null) {
      await startNewSession(userId);
    }

    if (_knowledgeBase.isEmpty) {
      await loadKnowledgeBase();
    }

    final online = await _connectivity.isConnected;
    if (!online) {
      await _markCurrentSessionOffline();
    }

    final hadAssistantBefore =
      _currentMessages.any((m) => m.role == MessageRole.assistant);
    final hasAttachedImage =
      attachedImageBytes != null && attachedImageBytes.isNotEmpty;
    final resolvedHintCropType = _resolveConversationCropHint(
      attachedDiagnosis: attachedDiagnosis,
      explicitHint: hintCropType,
    );
    final requiresFreshImage =
      attachedDiagnosis == null && !hasAttachedImage && resolvedHintCropType == null;

    final conversationHistory = _recentConversationHistory();

    // Upload image to Supabase Storage so it survives history loads
    final msgId = const Uuid().v4();
    String? uploadedImageUrl;
    if (online && hasAttachedImage) {
      uploadedImageUrl = await _supabase.uploadChatImage(
        userId: userId,
        messageId: msgId,
        bytes: attachedImageBytes,
      );
    }

    final userMsg = ChatMessageModel(
      id: msgId,
      sessionId: _currentSession!.id,
      userId: userId,
      role: MessageRole.user,
      content: content,
      createdAt: DateTime.now(),
      metadata:
          uploadedImageUrl != null ? {'image_url': uploadedImageUrl} : null,
        imageBytes: hasAttachedImage
          ? Uint8List.fromList(attachedImageBytes)
          : null,
      isVideoFrame: isVideoFrame,
    );
    _currentMessages.add(userMsg);
    notifyListeners();

    await _saveMessage(userMsg);

    // Build AI response
    _isTyping = true;
    notifyListeners();

    late final String aiContent;
    Map<String, dynamic>? aiMetadata;

    if (requiresFreshImage) {
      aiContent = _buildImageRequiredResponse();
      aiMetadata = {
        'model': 'local-request-photo',
        'sources': const <String>[],
        'recommended_actions': const <String>[],
        'warnings': const <String>[],
        'in_app_crop_scope': false,
        'show_treatment_card': false,
      };
    } else {
      try {
        if (!online) {
          throw Exception('offline');
        }
        final backendResponse = await _aiBackend.sendChatMessage(
          userMessage: content,
          cropId: attachedDiagnosis?.cropId.isNotEmpty == true
              ? attachedDiagnosis!.cropId
              : _currentSession?.cropId,
          diagnosis: attachedDiagnosis,
          imageBytes: attachedImageBytes,
          imageMimeType: attachedImageMimeType,
          conversationHistory: conversationHistory,
          hintCropType: resolvedHintCropType,
        );
        final inferredDiseaseName =
            (attachedDiagnosis?.diseaseName.trim().isNotEmpty ?? false)
                ? attachedDiagnosis!.diseaseName.trim()
                : _inferDiseaseName(backendResponse.answer);
        final inferredCropType = _inferCropType(
          labelKey: attachedDiagnosis?.labelKey,
          diseaseName: inferredDiseaseName,
          aiContent: backendResponse.answer,
        );
        final inferredLabelKey =
            (attachedDiagnosis?.labelKey?.trim().isNotEmpty ?? false)
                ? attachedDiagnosis!.labelKey!.trim()
                : _inferLabelKey(
                    diseaseName: inferredDiseaseName,
                    cropType: inferredCropType,
                  );
        final normalizedActions = backendResponse.recommendedActions.isNotEmpty
            ? backendResponse.recommendedActions
            : _extractTreatmentActionsFromContent(
                backendResponse.answer,
                inferredCropType: inferredCropType,
                inferredDiseaseName: inferredDiseaseName,
              );
        // Store recommended_actions in metadata but DON'T append them to text
        // — they are rendered as an interactive checklist in the UI.
        aiContent = _formatBackendResponse(backendResponse);
        final showTreatmentCard =
            !hadAssistantBefore &&
            _shouldShowTreatmentCard(
              attachedDiagnosis: attachedDiagnosis,
              recommendedActions: normalizedActions,
              inferredDiseaseName: inferredDiseaseName,
              inferredCropType: inferredCropType,
            );
        aiMetadata = {
          'model': backendResponse.model,
          'sources': backendResponse.sources,
          'recommended_actions':
              showTreatmentCard ? normalizedActions : const <String>[],
          'warnings': showTreatmentCard
              ? backendResponse.warnings
              : const <String>[],
          'disease_name': inferredDiseaseName,
          'crop_type': inferredCropType,
          'label_key': inferredLabelKey,
          'severity': attachedDiagnosis?.severity.value ?? 'moderate',
          'in_app_crop_scope': backendResponse.inAppCropScope ||
              attachedDiagnosis != null ||
              _supportedTreatmentCardCrops.contains(inferredCropType),
          'show_treatment_card': showTreatmentCard,
        };
      } catch (error) {
        await Future.delayed(const Duration(milliseconds: 500));
        final fallbackDiseaseName =
            (attachedDiagnosis?.diseaseName ?? '').trim();
        final fallbackCropType = attachedDiagnosis != null
            ? _inferCropType(
                labelKey: attachedDiagnosis.labelKey,
                diseaseName: fallbackDiseaseName,
                aiContent: '',
              )
            : (resolvedHintCropType ?? '');
        final fallbackLabelKey =
            (attachedDiagnosis?.labelKey ?? '').trim().isNotEmpty
                ? attachedDiagnosis!.labelKey!.trim()
                : (fallbackDiseaseName.isNotEmpty && fallbackCropType.isNotEmpty
                    ? _inferLabelKey(
                        diseaseName: fallbackDiseaseName,
                        cropType: fallbackCropType,
                      )
                    : '');
        final fallbackActions = _fallbackRecommendedActions(
          attachedDiagnosis: attachedDiagnosis,
          inferredDiseaseName: fallbackDiseaseName,
          inferredCropType: fallbackCropType,
        );
        final showTreatmentCard =
            !hadAssistantBefore &&
            _shouldShowTreatmentCard(
              attachedDiagnosis: attachedDiagnosis,
              recommendedActions: fallbackActions,
              inferredDiseaseName: fallbackDiseaseName,
              inferredCropType: fallbackCropType,
            );
        aiContent = _buildBackendUnavailableResponse(
          content,
          attachedDiagnosis: attachedDiagnosis,
          hasAttachedImage: hasAttachedImage,
          hintCropType: resolvedHintCropType,
          error: error,
        );
        aiMetadata = {
          'model': 'local-fallback',
          'sources': const <String>[],
          'recommended_actions':
              showTreatmentCard ? fallbackActions : const <String>[],
          'warnings': [
            hasAttachedImage
                ? 'Online AI backend unavailable; limited offline guidance was used for this image.'
                : 'Upload a crop photo to get a diagnosis when online AI is unavailable.'
          ],
          'backend_error': error.toString(),
          'backend_base_url': _aiBackend.baseUrl,
          'disease_name': fallbackDiseaseName,
          'crop_type': fallbackCropType,
          'label_key': fallbackLabelKey,
          'severity': attachedDiagnosis?.severity.value ?? 'moderate',
          'in_app_crop_scope': attachedDiagnosis != null || hasAttachedImage,
          'show_treatment_card': showTreatmentCard,
        };
      }
    }

    final aiMsg = ChatMessageModel(
      id: const Uuid().v4(),
      sessionId: _currentSession!.id,
      userId: userId,
      role: MessageRole.assistant,
      content: aiContent,
      metadata: aiMetadata,
      createdAt: DateTime.now(),
    );

    _currentMessages.add(aiMsg);
    _isTyping = false;

    await _saveMessage(aiMsg);

    // Add an "Add to My Crops" suggestion card when:
    //   - a local diagnosis was attached (scan result), OR
    //   - an image was sent and the AI returned treatment steps (GPT vision)
    // Treatment checklist + "Add to My Crops" only on first diagnosis turn with backend consent
    final showTreatmentCard = aiMetadata['show_treatment_card'] == true;
    if (showTreatmentCard) {
      final inferredDiseaseName =
          (attachedDiagnosis?.diseaseName.trim().isNotEmpty ?? false)
              ? attachedDiagnosis!.diseaseName.trim()
              : (aiMetadata['disease_name'] as String? ?? '').trim();
      final inferredCropType = _inferCropType(
        labelKey: attachedDiagnosis?.labelKey,
        diseaseName: inferredDiseaseName,
        aiContent: (aiMetadata['crop_type'] as String? ?? aiContent),
      );
      final isSupportedCrop =
          _supportedTreatmentCardCrops.contains(inferredCropType);
      final inferredLabelKey =
          (attachedDiagnosis?.labelKey?.trim().isNotEmpty ?? false)
              ? attachedDiagnosis!.labelKey!.trim()
              : ((aiMetadata['label_key'] as String? ?? '').trim().isNotEmpty
                  ? (aiMetadata['label_key'] as String).trim()
                  : _inferLabelKey(
                      diseaseName: inferredDiseaseName,
                      cropType: inferredCropType,
                    ));
      if (!isSupportedCrop || inferredDiseaseName.isEmpty) {
        notifyListeners();
        return;
      }
      final cardMsg = ChatMessageModel(
        id: const Uuid().v4(),
        sessionId: _currentSession!.id,
        userId: userId,
        role: MessageRole.system,
        content: '',
        metadata: {
          'type': 'add_crop_suggestion',
          'disease_name': inferredDiseaseName,
          'label_key': inferredLabelKey,
          'severity': attachedDiagnosis?.severity.value ?? 'moderate',
          'crop_type': inferredCropType,
          'summary': aiContent,
          'model_name': aiMetadata['model'],
          'image_url': uploadedImageUrl,
          'recommended_actions':
              (aiMetadata['recommended_actions'] as List<dynamic>? ?? []),
        },
        createdAt: DateTime.now(),
      );
      _currentMessages.add(cardMsg);
      await _saveMessage(cardMsg);
    }

    // Update session last_message_at
    try {
      await _supabase.client
          .from('chat_sessions')
          .update({'last_message_at': DateTime.now().toIso8601String()}).eq(
              'id', _currentSession!.id);
    } catch (_) {}

    notifyListeners();
  }

  List<Map<String, String>> _recentConversationHistory({int limit = 6}) {
    final history = <Map<String, String>>[];

    for (final message in _currentMessages.reversed) {
      if (message.role == MessageRole.system) {
        continue;
      }

      final content = message.content.trim();
      if (content.isEmpty) {
        continue;
      }

      history.add({
        'role': message.role.value,
        'content': content,
      });

      if (history.length == limit) {
        break;
      }
    }

    return history.reversed.toList();
  }

  bool _shouldShowTreatmentCard({
    required DiagnosisModel? attachedDiagnosis,
    required List<String> recommendedActions,
    required String inferredDiseaseName,
    required String inferredCropType,
  }) {
    if (recommendedActions.isEmpty) {
      return false;
    }

    final diseaseName =
        attachedDiagnosis?.diseaseName.trim() ?? inferredDiseaseName;
    if (diseaseName.isEmpty) {
      return false;
    }

    final cropType = attachedDiagnosis != null
        ? _inferCropType(
            labelKey: attachedDiagnosis.labelKey,
            diseaseName: attachedDiagnosis.diseaseName,
            aiContent: '',
          )
        : inferredCropType;
    return _supportedTreatmentCardCrops.contains(cropType);
  }

  // ─── AI Response Builder ─────────────────────────────────────────────────

  String _buildAIResponse(
    String userMessage, {
    DiagnosisModel? attachedDiagnosis,
    bool hasAttachedImage = false,
    String? hintCropType,
  }) {
    final lower = userMessage.toLowerCase();
    final normalizedHint = (hintCropType ?? '').trim().toLowerCase();

    // If there's an attached diagnosis, provide treatment advice
    if (attachedDiagnosis != null) {
      final kb = _knowledgeBase.firstWhere(
        (k) {
          final diagnosisLabelKey = attachedDiagnosis.labelKey?.trim();
          final knowledgeLabelKey = k.labelKey?.trim();
          if (diagnosisLabelKey != null &&
              diagnosisLabelKey.isNotEmpty &&
              knowledgeLabelKey != null &&
              knowledgeLabelKey.isNotEmpty) {
            return knowledgeLabelKey == diagnosisLabelKey;
          }
          return k.diseaseName.toLowerCase() ==
              attachedDiagnosis.diseaseName.toLowerCase();
        },
        orElse: () => _knowledgeBase.isNotEmpty
            ? _knowledgeBase.first
            : DiseaseKnowledgeModel(
                id: '',
                cropType: CropType.tomato,
                labelKey: attachedDiagnosis.labelKey,
                diseaseName: attachedDiagnosis.diseaseName,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
      );
      return _formatDiagnosisResponse(attachedDiagnosis, kb);
    }

    if (!hasAttachedImage) {
      if (normalizedHint.isNotEmpty) {
        final cropKnowledge = _knowledgeBase
            .where((kb) => kb.cropType.value == normalizedHint)
            .toList();

        for (final kb in cropKnowledge) {
          final diseaseName = kb.diseaseName.toLowerCase();
          if (diseaseName.isNotEmpty && lower.contains(diseaseName)) {
            return _formatKbResponse(kb);
          }
        }

        if (_looksLikeProductQuestion(lower)) {
          return _buildProductFallbackResponse(normalizedHint, cropKnowledge);
        }

        if (cropKnowledge.isNotEmpty) {
          return _buildCropFollowUpResponse(normalizedHint, cropKnowledge);
        }
      }

      return _buildImageRequiredResponse();
    }

    return _buildUncertainImageResponse();

    // Search knowledge base for disease mentions

    // Search knowledge base for disease mentions
    for (final kb in _knowledgeBase) {
      if (lower.contains(kb.diseaseName.toLowerCase()) ||
          lower.contains(kb.cropType.name.toLowerCase())) {
        return _formatKbResponse(kb);
      }
    }

    // Keyword responses
    if (lower.contains('water') || lower.contains('irrigat')) {
      return 'Proper irrigation is critical for crop health. For most vegetable crops:\n\n• Water early morning (6–9 AM) to reduce fungal disease risk\n• Avoid overhead watering — use drip irrigation when possible\n• Check soil moisture 2–3 inches deep before watering\n• Reduce irrigation when rainfall and soil moisture are already high\n\nWould you like advice for a specific crop?';
    }
    if (lower.contains('pest') ||
        lower.contains('insect') ||
        lower.contains('bug')) {
      return 'To identify a pest, describe its appearance or upload an image using the camera icon. Common vegetable pests include:\n\n• Aphids — tiny green or black insects on leaf undersides\n• Diamondback moth larvae — small green caterpillars on brassicas like pechay\n• Whiteflies — white flying insects that cause yellowing\n• Leaf miners — pests that create pale trails inside leaves\n\nWhich crop are you concerned about?';
    }
    if (lower.contains('fertili') || lower.contains('nutrient')) {
      return 'Nutrient management for vegetables:\n\n• Nitrogen (N) — promotes leafy growth; yellowing leaves may indicate deficiency\n• Phosphorus (P) — essential for root development\n• Potassium (K) — strengthens disease resistance\n\nFor organic options, compost, vermicast, or fish emulsion can help support crop recovery. Would you like a specific fertilizer schedule?';
    }
    if (lower.contains('yellow') ||
        lower.contains('wilting') ||
        lower.contains('spot')) {
      for (final kb in _knowledgeBase) {
        if (kb.symptoms != null &&
            kb.symptoms!
                .any((s) => s.toLowerCase().contains(lower.split(' ').first))) {
          return _formatKbResponse(kb);
        }
      }
      return 'Yellowing, wilting, or spots on leaves can indicate several issues:\n\n• **Disease** — fungal or bacterial infection (upload an image for diagnosis)\n• **Nutrient deficiency** — especially nitrogen or iron\n• **Overwatering** — root rot can cause wilting\n• **Pest damage** — check leaf undersides for insects\n\nFor accurate diagnosis, tap the camera icon to upload a photo of the affected leaves.';
    }
    if (lower.contains('hello') ||
        lower.contains('hi') ||
        lower.contains('help')) {
      return 'Hello! I\'m your CropCare AI Vegetable Doctor. I can help you with:\n\n• 🔍 **Identify diseases** — describe symptoms or upload a photo\n• 💊 **Treatment protocols** — organic and clinical options\n• 💧 **Watering & fertilizer** schedules\n• 🌱 **Crop health monitoring** for Tomato, Pechay, Pepper, Eggplant, and Squash\n\nWhat\'s going on with your crops today?';
    }

    return 'Thank you for your question. Based on the information currently available, I recommend monitoring your crops closely for any changes in leaf color, texture, or growth patterns.\n\nFor the most accurate diagnosis, please:\n1. Upload a clear photo of the affected area\n2. Describe specific symptoms you\'re observing\n3. Mention which crop and plot is affected\n\nI\'m here to help with your crop health.';
  }

  String _formatKbResponse(DiseaseKnowledgeModel kb) {
    final steps = kb.treatmentSteps?.take(3).toList() ?? [];
    final stepsText = steps.isNotEmpty
        ? steps
            .asMap()
            .entries
            .map((e) => '${e.key + 1}. ${e.value}')
            .join('\n')
        : 'Consult local agricultural extension for treatment options.';

    return '**${kb.diseaseName}** detected on ${kb.cropType.name}.\n\n'
        '${kb.description ?? ''}\n\n'
        '**Symptoms:** ${kb.symptoms?.join(', ') ?? 'See field observations'}\n\n'
        '**Treatment Steps:**\n$stepsText\n\n'
        '**Estimated recovery:** ${kb.estimatedRecoveryDays ?? 'Varies'} days\n\n'
        '${kb.cautionNotes != null ? '⚠️ ${kb.cautionNotes}' : ''}';
  }

  String _formatDiagnosisResponse(DiagnosisModel d, DiseaseKnowledgeModel? kb) {
    final confidence = d.confidenceScore != null
        ? '${(d.confidenceScore! * 100).toStringAsFixed(0)}%'
        : 'N/A';
    return '**${d.diseaseName}** — ${d.severity.name.toUpperCase()} severity ($confidence confidence)\n\n'
        '${d.summary ?? kb?.description ?? ''}\n\n'
        '${kb != null ? _formatKbResponse(kb) : ''}';
  }

  String _formatBackendResponse(AiBackendChatResponse response) {
    return response.answer.trim().isNotEmpty
        ? response.answer.trim()
        : 'I could not generate a response right now.';
  }

  String _buildBackendUnavailableResponse(
    String userMessage, {
    DiagnosisModel? attachedDiagnosis,
    required bool hasAttachedImage,
    String? hintCropType,
    Object? error,
  }) {
    final fallback = _buildAIResponse(
      userMessage,
      attachedDiagnosis: attachedDiagnosis,
      hasAttachedImage: hasAttachedImage,
      hintCropType: hintCropType,
    );
    final detail = kDebugMode && error != null
        ? '\n\nDebug: ${_aiBackend.baseUrl} failed with $error'
        : '';
    return 'Online AI is unavailable right now, so I am using offline crop guidance only.\n\n'
        '$fallback$detail';
  }

  String _buildImageRequiredResponse() {
    return 'Please upload or capture a clear photo of the affected crop first before I give a diagnosis or treatment plan.\n\n'
        'For the best result:\n'
        '1. Show the affected leaf or fruit up close\n'
        '2. Keep the image bright and in focus\n'
        '3. Add a short note about what changed\n\n'
        'Once the model has an image to analyze, I can give a more accurate diagnosis and next steps.';
  }

  String _buildUncertainImageResponse() {
    return 'I could not confidently confirm a diagnosis from this image offline.\n\n'
        'Please try one of these next steps:\n'
        '1. Retake the photo with a closer, sharper view of the affected area\n'
        '2. Capture the front and back of the leaf in good lighting\n'
        '3. If you are online, try again for a more comprehensive AI review\n\n'
        'I will avoid guessing a disease or treatment until the model can identify the crop more reliably.';
  }

  String _buildCropFollowUpResponse(
    String cropType,
    List<DiseaseKnowledgeModel> cropKnowledge,
  ) {
    final diseaseNames = cropKnowledge
        .map((kb) => kb.diseaseName.trim())
        .where((name) => name.isNotEmpty)
        .take(3)
        .join(', ');

    return 'We are still focused on your $cropType crop. Ask about symptoms, treatment timing, or a product you want to check, and I will keep the advice specific to $cropType.\n\n'
        '${diseaseNames.isNotEmpty ? 'Common $cropType issues in my offline guide include $diseaseNames.' : 'Share the symptom, disease name, or product label and I will help you narrow it down.'}';
  }

  String _buildProductFallbackResponse(
    String cropType,
    List<DiseaseKnowledgeModel> cropKnowledge,
  ) {
    final exampleSteps = <String>[];
    for (final knowledge in cropKnowledge) {
      for (final step in [...?knowledge.treatmentSteps, ...?knowledge.preventionSteps]) {
        final normalized = step.trim();
        if (normalized.isNotEmpty && !exampleSteps.contains(normalized)) {
          exampleSteps.add(normalized);
        }
        if (exampleSteps.length == 3) {
          break;
        }
      }
      if (exampleSteps.length == 3) {
        break;
      }
    }

    final examplesText = exampleSteps.isNotEmpty
        ? exampleSteps.asMap().entries.map((entry) => '${entry.key + 1}. ${entry.value}').join('\n')
        : 'Tell me the product name or active ingredient and I will compare it against the offline crop guidance I have for $cropType.';

    return 'I can still help review a product for your $cropType crop offline, but I cannot verify live web listings right now.\n\n'
        'Share the product name or active ingredient and I will compare it against the crop guidance I already have.\n\n'
        'Examples from my $cropType knowledge base:\n$examplesText\n\n'
        'Please still verify the label for crop registration, dosage, and pre-harvest interval before applying it.';
  }

  bool _looksLikeProductQuestion(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) {
      return false;
    }

    return lower.contains('product') ||
        lower.contains('brand') ||
        lower.contains('spray') ||
        lower.contains('fungicide') ||
        lower.contains('bactericide') ||
        lower.contains('pesticide') ||
        lower.contains('insecticide') ||
        lower.contains('miticide') ||
        lower.contains('fertilizer') ||
        lower.contains('fertiliser') ||
        lower.contains('active ingredient') ||
        lower.contains('can i use') ||
        lower.contains('should i use') ||
        lower.contains('recommend') ||
        lower.contains('copper') ||
        lower.contains('mancozeb') ||
        lower.contains('abamectin') ||
        lower.contains('neem');
  }

  // ─── Save ────────────────────────────────────────────────────────────────

  Future<void> _saveMessage(ChatMessageModel msg) async {
    try {
      await _supabase.insertChatMessage({
        'id': msg.id,
        'session_id': msg.sessionId,
        'user_id': msg.userId,
        'role': msg.role.value,
        'content': msg.content,
        'metadata': msg.metadata != null ? jsonEncode(msg.metadata) : null,
        'created_at': msg.createdAt.toIso8601String(),
      });
    } catch (_) {}
    await _db.upsertRow(AppConstants.chatMessagesTable, msg.toMap());
  }

  Future<void> _markCurrentSessionOffline() async {
    final current = _currentSession;
    if (current == null || current.isOfflineSession) {
      return;
    }

    final updated = current.copyWith(
      isOfflineSession: true,
      updatedAt: DateTime.now(),
    );
    _currentSession = updated;

    final index = _sessions.indexWhere((session) => session.id == updated.id);
    if (index != -1) {
      _sessions[index] = updated;
    }

    await _db.upsertRow(AppConstants.chatSessionsTable, updated.toMap());
  }

  Map<String, dynamic> _sessionRemoteMap(ChatSessionModel s) {
    final m = s.toMap();
    m['is_offline_session'] = s.isOfflineSession;
    m['is_deleted'] = s.isDeleted;
    return m;
  }

  void clearSession() {
    _currentSession = null;
    _currentMessages = [];
    notifyListeners();
  }

  void clear() {
    _sessions = [];
    _currentMessages = [];
    _currentSession = null;
    notifyListeners();
  }

  String _inferDiseaseName(String aiContent) {
    final normalized = aiContent.toLowerCase();
    for (final knowledge in _knowledgeBase) {
      final diseaseName = knowledge.diseaseName.trim();
      if (diseaseName.isNotEmpty &&
          normalized.contains(diseaseName.toLowerCase())) {
        return diseaseName;
      }
    }
    return '';
  }

  List<String> _extractTreatmentActionsFromContent(
    String aiContent, {
    required String inferredCropType,
    required String inferredDiseaseName,
  }) {
    if (aiContent.trim().isEmpty ||
        inferredDiseaseName.trim().isEmpty ||
        !_supportedTreatmentCardCrops.contains(inferredCropType)) {
      return const [];
    }

    final actions = <String>[];
    final sections = [
      _extractSection(
        aiContent,
        'What to do now',
        const [
          'Next steps',
          'Immediate action',
          'Treatment',
          'Prevention tip',
          'Prevention',
          'Warnings',
        ],
      ),
      _extractSection(
        aiContent,
        'Next steps',
        const ['Immediate action', 'Treatment', 'Prevention tip', 'Prevention'],
      ),
      _extractSection(
        aiContent,
        'Recommended actions',
        const ['Next steps', 'Immediate action', 'Treatment', 'Prevention'],
      ),
      _extractSection(
        aiContent,
        'Immediate action',
        const ['Treatment', 'Prevention tip', 'Prevention'],
      ),
      _extractSection(
        aiContent,
        'Treatment',
        const ['Prevention tip', 'Prevention', 'Warnings'],
      ),
    ];

    for (final section in sections) {
      if (section.trim().isEmpty) {
        continue;
      }
      actions.addAll(_splitIntoActionSentences(section));
    }

    final deduped = <String>[];
    for (final action in actions) {
      final normalized = action.trim();
      if (normalized.isNotEmpty && !deduped.contains(normalized)) {
        deduped.add(normalized);
      }
    }
    if (deduped.isNotEmpty) {
      return deduped.take(7).toList();
    }

    final fallbackActions = _splitIntoActionSentences(aiContent)
        .where(_looksLikeActionSentence)
        .where((sentence) => !_looksLikeObservationSentence(sentence))
        .toList();
    final fallbackDeduped = <String>[];
    for (final action in fallbackActions) {
      if (!fallbackDeduped.contains(action)) {
        fallbackDeduped.add(action);
      }
    }
    return fallbackDeduped.take(7).toList();
  }

  List<String> _fallbackRecommendedActions({
    DiagnosisModel? attachedDiagnosis,
    required String inferredDiseaseName,
    required String inferredCropType,
  }) {
    if (attachedDiagnosis == null &&
        inferredDiseaseName.trim().isEmpty &&
        inferredCropType.trim().isEmpty) {
      return const [];
    }

    DiseaseKnowledgeModel? knowledge;
    if (attachedDiagnosis != null) {
      knowledge = _knowledgeForDiagnosis(attachedDiagnosis);
    }
    knowledge ??= _knowledgeForDisease(
      labelKey: attachedDiagnosis?.labelKey,
      diseaseName: inferredDiseaseName,
      cropType: inferredCropType,
    );
    if (knowledge == null) {
      return const [];
    }

    final steps = <String>[
      ...?knowledge.treatmentSteps,
      ...?knowledge.preventionSteps,
    ];
    final deduped = <String>[];
    for (final step in steps) {
      final normalized = step.trim();
      if (normalized.isNotEmpty && !deduped.contains(normalized)) {
        deduped.add(normalized);
      }
    }
    return deduped.take(7).toList();
  }

  DiseaseKnowledgeModel? _knowledgeForDiagnosis(DiagnosisModel diagnosis) {
    return _knowledgeForDisease(
      labelKey: diagnosis.labelKey,
      diseaseName: diagnosis.diseaseName,
      cropType: _inferCropType(
        labelKey: diagnosis.labelKey,
        diseaseName: diagnosis.diseaseName,
        aiContent: '',
      ),
    );
  }

  DiseaseKnowledgeModel? _knowledgeForDisease({
    String? labelKey,
    required String diseaseName,
    required String cropType,
  }) {
    final normalizedLabelKey = (labelKey ?? '').trim();
    if (normalizedLabelKey.isNotEmpty) {
      for (final knowledge in _knowledgeBase) {
        if ((knowledge.labelKey ?? '').trim() == normalizedLabelKey) {
          return knowledge;
        }
      }
    }

    final normalizedDiseaseName = diseaseName.trim().toLowerCase();
    final normalizedCropType = cropType.trim().toLowerCase();
    for (final knowledge in _knowledgeBase) {
      final matchesDisease =
          knowledge.diseaseName.trim().toLowerCase() == normalizedDiseaseName;
      final matchesCrop = normalizedCropType.isEmpty ||
          knowledge.cropType.value == normalizedCropType;
      if (matchesDisease && matchesCrop) {
        return knowledge;
      }
    }

    if (normalizedDiseaseName.isEmpty) {
      return null;
    }

    for (final knowledge in _knowledgeBase) {
      if (knowledge.diseaseName.trim().toLowerCase() == normalizedDiseaseName) {
        return knowledge;
      }
    }
    return null;
  }

  bool _looksLikeObservationSentence(String text) {
    final lower = text.trim().toLowerCase();
    return lower.startsWith('i see ') ||
        lower.startsWith('this looks') ||
        lower.startsWith('it looks') ||
        lower.startsWith('the image') ||
        lower.startsWith('this image') ||
        lower.startsWith('i could') ||
        lower.startsWith('it could') ||
        lower.contains(' most like ');
  }

  bool _looksLikeActionSentence(String text) {
    final lower = text.trim().toLowerCase();
    return lower.startsWith('remove ') ||
        lower.startsWith('water ') ||
        lower.startsWith('avoid ') ||
        lower.startsWith('clear ') ||
        lower.startsWith('check ') ||
        lower.startsWith('apply ') ||
        lower.startsWith('use ') ||
        lower.startsWith('keep ') ||
        lower.startsWith('monitor ') ||
        lower.startsWith('prune ') ||
        lower.startsWith('improve ') ||
        lower.startsWith('spray ') ||
        lower.startsWith('isolate ') ||
        lower.startsWith('destroy ') ||
        lower.startsWith('disinfect ') ||
        lower.startsWith('retake ') ||
        lower.startsWith('capture ') ||
        lower.startsWith('upload ') ||
        lower.startsWith('if ');
  }

  String _extractSection(String text, String label, List<String> nextLabels) {
    final normalizedText = text.replaceAll('\n', ' ');
    final lowerText = normalizedText.toLowerCase();
    final labelToken = '${label.toLowerCase()}:';
    final start = lowerText.indexOf(labelToken);
    if (start == -1) {
      return '';
    }

    final contentStart = start + labelToken.length;
    var end = normalizedText.length;
    for (final nextLabel in nextLabels) {
      final nextIndex =
          lowerText.indexOf('${nextLabel.toLowerCase()}:', contentStart);
      if (nextIndex != -1 && nextIndex < end) {
        end = nextIndex;
      }
    }

    return normalizedText.substring(contentStart, end).trim();
  }

  List<String> _splitIntoActionSentences(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return const [];
    }

    return normalized
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  String _inferLabelKey({
    required String diseaseName,
    required String cropType,
  }) {
    final normalizedDisease = diseaseName.trim().toLowerCase();
    final normalizedCropType = cropType.trim().toLowerCase();
    for (final knowledge in _knowledgeBase) {
      final matchesDisease =
          knowledge.diseaseName.trim().toLowerCase() == normalizedDisease;
      final matchesCrop = knowledge.cropType.value == normalizedCropType;
      if (matchesDisease && matchesCrop) {
        return knowledge.labelKey ?? '';
      }
    }
    for (final knowledge in _knowledgeBase) {
      if (knowledge.diseaseName.trim().toLowerCase() == normalizedDisease) {
        return knowledge.labelKey ?? '';
      }
    }
    return '';
  }

  /// Infers crop type string from labelKey, diseaseName, or AI response content.
  static String _inferCropType({
    String? labelKey,
    required String diseaseName,
    required String aiContent,
  }) {
    final lk = (labelKey ?? '').toLowerCase();
    final dn = diseaseName.toLowerCase();
    final ai = aiContent.toLowerCase();
    for (final entry in const {
      'tomato': ['tomato'],
      'pepper': ['pepper', 'capsicum'],
      'eggplant': ['eggplant', 'talong'],
      'pechay': ['pechay', 'bok choy', 'bokchoy'],
      'squash': ['squash', 'kalabasa'],
      'corn': ['corn', 'maize'],
    }.entries) {
      for (final kw in entry.value) {
        if (lk.contains(kw) || dn.contains(kw) || ai.contains(kw)) {
          return entry.key;
        }
      }
    }
    return '';
  }

  static String? resolveHintCropType({
    DiagnosisModel? attachedDiagnosis,
    String? explicitHint,
  }) {
    final ex = (explicitHint ?? '').trim().toLowerCase();
    if (ex.isNotEmpty) return ex;
    if (attachedDiagnosis == null) return null;
    final fromDx = _inferCropType(
      labelKey: attachedDiagnosis.labelKey,
      diseaseName: attachedDiagnosis.diseaseName,
      aiContent: '',
    );
    return fromDx.isEmpty ? null : fromDx;
  }

  String? _resolveConversationCropHint({
    DiagnosisModel? attachedDiagnosis,
    String? explicitHint,
  }) {
    final direct = resolveHintCropType(
      attachedDiagnosis: attachedDiagnosis,
      explicitHint: explicitHint,
    );
    if (direct != null) {
      return direct;
    }

    for (final message in _currentMessages.reversed) {
      final metadata = message.metadata;
      if (metadata == null) {
        continue;
      }

      final cropType = (metadata['crop_type'] as String? ?? '').trim().toLowerCase();
      if (cropType.isNotEmpty) {
        return cropType;
      }
    }

    return null;
  }
}
