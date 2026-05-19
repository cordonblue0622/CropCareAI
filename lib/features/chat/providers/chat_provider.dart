import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/utils/label_formatter.dart';
import '../../../core/utils/image_reference.dart';
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
      final fetchedSessions = rows.map(ChatSessionModel.fromMap).toList();
      await _db.upsertRows(
        AppConstants.chatSessionsTable,
        fetchedSessions.map((session) => session.toMap()),
      );
      _sessions = await _filterHistorySessions(fetchedSessions);
    } catch (_) {
      final rows =
          await _db.queryByUserId(AppConstants.chatSessionsTable, userId);
      final fetchedSessions = rows.map(ChatSessionModel.fromMap).toList();
      _sessions = await _filterHistorySessions(fetchedSessions);
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
    bool hideMessageTextInUi = false,
    DiagnosisModel? attachedDiagnosis,
    List<int>? attachedImageBytes,
    String? attachedAudioPath,
    String? attachedVideoPath,
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

    final hasShownAddCropSuggestion = _currentMessages.any(
      (m) =>
          m.role == MessageRole.system &&
          m.metadata?['type'] == 'add_crop_suggestion',
    );
    final hasAttachedImage =
        attachedImageBytes != null && attachedImageBytes.isNotEmpty;
    final resolvedHintCropType = _resolveConversationCropHint(
      attachedDiagnosis: attachedDiagnosis,
      explicitHint: hintCropType,
    );
    final requiresFreshImage = attachedDiagnosis == null &&
        !hasAttachedImage &&
        _requiresFreshImageForMessage(
          content,
          resolvedHintCropType: resolvedHintCropType,
        );

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
    final localImageReference =
        hasAttachedImage ? buildInlineImageDataUrl(attachedImageBytes) : null;
    final persistedImageReference = uploadedImageUrl ?? localImageReference;
    final normalizedVideoPath = attachedVideoPath?.trim();
    final userMetadata = <String, dynamic>{
      if (persistedImageReference != null) 'image_url': persistedImageReference,
      if (normalizedVideoPath != null && normalizedVideoPath.isNotEmpty)
        'video_url': normalizedVideoPath,
      if (normalizedVideoPath != null &&
          normalizedVideoPath.isNotEmpty &&
          persistedImageReference != null)
        'video_poster_url': persistedImageReference,
      if (attachedAudioPath != null && attachedAudioPath.trim().isNotEmpty)
        'audio_path': attachedAudioPath.trim(),
      if (hideMessageTextInUi) 'hide_text': true,
    };

    final userMsg = ChatMessageModel(
      id: msgId,
      sessionId: _currentSession!.id,
      userId: userId,
      role: MessageRole.user,
      content: content,
      createdAt: DateTime.now(),
        metadata: userMetadata.isEmpty ? null : userMetadata,
      imageBytes: hasAttachedImage &&
              (normalizedVideoPath == null || normalizedVideoPath.isEmpty)
          ? Uint8List.fromList(attachedImageBytes)
          : null,
      isVideoFrame: isVideoFrame &&
          (normalizedVideoPath == null || normalizedVideoPath.isEmpty),
    );
    _currentMessages.add(userMsg);
    notifyListeners();

    await _saveMessage(userMsg);

    // Build AI response
    _isTyping = true;
    notifyListeners();

    String aiContent = '';
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
        final backendDiseaseName = _inferDiseaseName(backendResponse.answer);
        final inferredDiseaseName = backendDiseaseName.isNotEmpty
            ? backendDiseaseName
            : (attachedDiagnosis?.diseaseName.trim().isNotEmpty ?? false)
                ? attachedDiagnosis!.diseaseName.trim()
                : '';
        final inferredCropType = _inferCropType(
          labelKey: backendDiseaseName.isNotEmpty
              ? null
              : attachedDiagnosis?.labelKey,
          diseaseName: inferredDiseaseName,
          aiContent: backendResponse.answer,
        );
        final effectiveCropType = inferredCropType.isNotEmpty
            ? inferredCropType
            : (resolvedHintCropType ?? '');
        final inferredLabelKey = backendDiseaseName.isNotEmpty
            ? _inferLabelKey(
                diseaseName: inferredDiseaseName,
                cropType: effectiveCropType,
              )
            : (attachedDiagnosis?.labelKey?.trim().isNotEmpty ?? false)
                ? attachedDiagnosis!.labelKey!.trim()
                : _inferLabelKey(
                    diseaseName: inferredDiseaseName,
                    cropType: effectiveCropType,
                  );
        final requiresMoreInput =
            _needsAdditionalInputResponse(backendResponse.answer);
        final backendAllowsPlan =
            backendResponse.showTreatmentUi && !requiresMoreInput;
        final normalizedActions = backendAllowsPlan
            ? (backendResponse.recommendedActions.isNotEmpty
                ? backendResponse.recommendedActions
                : _extractTreatmentActionsFromContent(
                    backendResponse.answer,
                    inferredCropType: effectiveCropType,
                    inferredDiseaseName: inferredDiseaseName,
                  ))
            : const <String>[];
        final effectiveActions = _resolveRecommendedActions(
          recommendedActions: normalizedActions,
          inferredDiseaseName: inferredDiseaseName,
          inferredCropType: effectiveCropType,
          allowHealthyFallback: backendAllowsPlan,
        );
        final planTitle = _planTitleForDiagnosis(inferredDiseaseName);
        // Store recommended_actions in metadata but DON'T append them to text
        // — they are rendered as an interactive checklist in the UI.
        aiContent = _formatBackendResponse(backendResponse);
        final showTreatmentCard = backendAllowsPlan &&
          backendResponse.inAppCropScope &&
          !hasShownAddCropSuggestion &&
            _shouldShowTreatmentCard(
              attachedDiagnosis: attachedDiagnosis,
              recommendedActions: effectiveActions,
              inferredDiseaseName: inferredDiseaseName,
              inferredCropType: effectiveCropType,
              aiContent: backendResponse.answer,
            );
        aiMetadata = {
          'model': backendResponse.model,
          'sources': backendResponse.sources,
          'recommended_actions':
              showTreatmentCard ? effectiveActions : const <String>[],
          'warnings':
              showTreatmentCard ? backendResponse.warnings : const <String>[],
          'disease_name': inferredDiseaseName,
          'crop_type': effectiveCropType,
          'label_key': inferredLabelKey,
          'severity': _resolveConversationSeverity(
            attachedDiagnosis: attachedDiagnosis,
            inferredDiseaseName: inferredDiseaseName,
            aiContent: backendResponse.answer,
          ).value,
          'in_app_crop_scope': backendResponse.inAppCropScope,
          'show_treatment_card': showTreatmentCard,
          if (showTreatmentCard) 'plan_title': planTitle,
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
        // Assign aiContent first so downstream checks can safely read it.
        aiContent = _buildBackendUnavailableResponse(
          content,
          attachedDiagnosis: attachedDiagnosis,
          hasAttachedImage: hasAttachedImage,
          hintCropType: resolvedHintCropType,
          error: error,
        );
        final requiresMoreInput = _needsAdditionalInputResponse(aiContent);
        final effectiveFallbackActions = _resolveRecommendedActions(
          recommendedActions: requiresMoreInput ? const [] : fallbackActions,
          inferredDiseaseName: fallbackDiseaseName,
          inferredCropType: fallbackCropType,
          allowHealthyFallback: !requiresMoreInput,
        );
        final showTreatmentCard = !requiresMoreInput &&
            !hasShownAddCropSuggestion &&
            _shouldShowTreatmentCard(
              attachedDiagnosis: attachedDiagnosis,
              recommendedActions: effectiveFallbackActions,
              inferredDiseaseName: fallbackDiseaseName,
              inferredCropType: fallbackCropType,
              aiContent: aiContent,
            );
        aiMetadata = {
          'model': 'local-fallback',
          'sources': const <String>[],
          'recommended_actions':
              showTreatmentCard ? effectiveFallbackActions : const <String>[],
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
          'severity': _resolveConversationSeverity(
            attachedDiagnosis: attachedDiagnosis,
            inferredDiseaseName: fallbackDiseaseName,
            aiContent: aiContent,
          ).value,
          'in_app_crop_scope': attachedDiagnosis != null || hasAttachedImage,
          'show_treatment_card': showTreatmentCard,
          if (showTreatmentCard)
            'plan_title': _planTitleForDiagnosis(fallbackDiseaseName),
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
      final inAppCropScope = aiMetadata['in_app_crop_scope'] == true;
      if (!inAppCropScope) {
        notifyListeners();
        return;
      }
      final assistantDiseaseName =
          (aiMetadata['disease_name'] as String? ?? '').trim();
      final preferAssistantDiagnosis = assistantDiseaseName.isNotEmpty &&
          (aiMetadata['model'] as String? ?? '').trim() != 'local-fallback';
      final inferredDiseaseName = preferAssistantDiagnosis
          ? assistantDiseaseName
          : (attachedDiagnosis?.diseaseName.trim().isNotEmpty ?? false)
              ? attachedDiagnosis!.diseaseName.trim()
              : assistantDiseaseName;
      final inferredCropType = _inferCropType(
        labelKey: preferAssistantDiagnosis ? null : attachedDiagnosis?.labelKey,
        diseaseName: inferredDiseaseName,
        aiContent: (aiMetadata['crop_type'] as String? ?? aiContent),
      );
      final isSupportedCrop =
          _supportedTreatmentCardCrops.contains(inferredCropType);
      final metadataLabelKey =
          (aiMetadata['label_key'] as String? ?? '').trim();
      final inferredLabelKey = preferAssistantDiagnosis
          ? (metadataLabelKey.isNotEmpty
              ? metadataLabelKey
              : _inferLabelKey(
                  diseaseName: inferredDiseaseName,
                  cropType: inferredCropType,
                ))
          : (attachedDiagnosis?.labelKey?.trim().isNotEmpty ?? false)
              ? attachedDiagnosis!.labelKey!.trim()
              : (metadataLabelKey.isNotEmpty
                  ? metadataLabelKey
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
            'severity': aiMetadata['severity'] ??
              attachedDiagnosis?.severity.value ??
              'moderate',
          'diagnosis_mode': preferAssistantDiagnosis
              ? DiagnosisMode.online.value
              : attachedDiagnosis?.diagnosisMode.value ??
                  ((aiMetadata['model'] as String?) == 'local-fallback'
                      ? DiagnosisMode.offline.value
                      : DiagnosisMode.online.value),
          'crop_type': inferredCropType,
          'summary': aiContent,
          'model_name': aiMetadata['model'],
          'image_url': persistedImageReference,
          'recommended_actions':
              (aiMetadata['recommended_actions'] as List<dynamic>? ?? []),
        },
        createdAt: DateTime.now(),
      );
      _currentMessages.add(cardMsg);
      await _saveMessage(cardMsg);
    }

    await _touchCurrentSession(
      activityAt: aiMsg.createdAt,
      preferredTitle: _buildConversationTitle(
        userContent: content,
        hideMessageTextInUi: hideMessageTextInUi,
        attachedDiagnosis: attachedDiagnosis,
        aiMetadata: aiMetadata,
        hintCropType: resolvedHintCropType,
      ),
    );

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
    required String aiContent,
  }) {
    if (recommendedActions.isEmpty) {
      return false;
    }

    if (_needsAdditionalInputResponse(aiContent)) {
      return false;
    }

    final diseaseName = inferredDiseaseName.trim().isNotEmpty
        ? inferredDiseaseName.trim()
        : (attachedDiagnosis?.diseaseName.trim() ?? '');
    if (diseaseName.isEmpty) {
      return false;
    }

    final cropType = inferredCropType.trim().isNotEmpty
        ? inferredCropType.trim()
        : attachedDiagnosis != null
            ? _inferCropType(
                labelKey: attachedDiagnosis.labelKey,
                diseaseName: attachedDiagnosis.diseaseName,
                aiContent: '',
              )
            : '';
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
    final inferredHint = _inferCropType(
      labelKey: null,
      diseaseName: '',
      aiContent: userMessage,
    );
    final effectiveHint = normalizedHint.isNotEmpty ? normalizedHint : inferredHint;

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
      if (_looksLikeGreeting(lower) || _looksLikeGeneralHelpQuestion(lower)) {
        return _buildGreetingResponse(effectiveHint);
      }

      if (effectiveHint.isNotEmpty) {
        final cropKnowledge = _knowledgeBase
            .where((kb) => kb.cropType.value == effectiveHint)
            .toList();

        for (final kb in cropKnowledge) {
          final diseaseName = kb.diseaseName.toLowerCase();
          if (diseaseName.isNotEmpty && lower.contains(diseaseName)) {
            return _formatKbResponse(kb);
          }
        }

        if (_looksLikeProductQuestion(lower)) {
          return _buildProductFallbackResponse(effectiveHint, cropKnowledge);
        }

        if (cropKnowledge.isNotEmpty) {
          return _buildCropFollowUpResponse(effectiveHint, cropKnowledge);
        }
      }

      if (_looksLikeProductQuestion(lower)) {
        return 'I can help with fertilizer and crop-product questions. Tell me the crop name or the product you want to check, or send a close leaf photo if you want a diagnosis.';
      }

      return _buildImageRequiredResponse();
    }

    return _buildUncertainImageResponse(
      userMessage,
      hintCropType: effectiveHint,
    );
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
    final requiresSignIn = error is AiBackendHttpException &&
      (error.statusCode == 401 || error.statusCode == 403);
    final detail = kDebugMode && error != null
        ? '\n\nDebug: ${_aiBackend.baseUrl} failed with $error'
        : '';
    final intro = requiresSignIn
      ? 'Online AI requires a signed-in account right now, so I am using offline crop guidance only.'
      : 'Online AI is unavailable right now, so I am using offline crop guidance only.';
    return '$intro\n\n'
        '$fallback$detail';
  }

  bool _looksLikeGreeting(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }

    const greetingPhrases = [
      'hi',
      'hello',
      'hey',
      'good morning',
      'good afternoon',
      'good evening',
    ];

    return greetingPhrases.any(
      (phrase) => normalized == phrase || normalized.startsWith('$phrase '),
    );
  }

  bool _looksLikeGeneralHelpQuestion(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }

    return normalized.contains('what can you do') ||
        normalized.contains('how can you help') ||
        normalized == 'help' ||
        normalized.startsWith('help me');
  }

  String _buildGreetingResponse(String normalizedHint) {
    if (normalizedHint.isNotEmpty) {
      return 'Hi. I\'m CropCare AI. Tell me what you need help with on your $normalizedHint crop, ask about care or products, or send a close leaf photo if you want a diagnosis.';
    }

    return 'Hi. I\'m CropCare AI. Tell me the crop and the problem you need help with, or send a close leaf photo if you want a diagnosis.';
  }

  bool _needsAdditionalInputResponse(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }

    // If the response contains diagnosis template markers it is a complete
    // diagnosis — never block the treatment card even when a secondary
    // photo-suggestion phrase also appears in the same reply.
    const diagnosisMarkers = [
      'what it is:',
      'immediate action:',
      'key symptoms:',
      'treatment:',
    ];
    if (diagnosisMarkers.any(normalized.contains)) {
      return false;
    }

    const phrases = [
      'clearer photo',
      'closer photo',
      'well-lit photo',
      'upload a clear',
      'retake the photo',
      'cannot verify',
      'can\'t verify',
      'cannot confirm',
      'can\'t confirm',
      'too unclear',
      'not a crop plant',
      'not a live plant',
      'picture of bell peppers on a screen',
      'photo of the actual plant',
      'need a closer photo',
      'need another photo',
    ];

    return phrases.any(normalized.contains);
  }

  String _buildImageRequiredResponse() {
    return 'Please upload or capture a clear photo of the affected crop first before I give a diagnosis or treatment plan.\n\n'
        'For the best result:\n'
        '1. Show the affected leaf or fruit up close\n'
        '2. Keep the image bright and in focus\n'
        '3. Add a short note about what changed\n\n'
        'Once the model has an image to analyze, I can give a more accurate diagnosis and next steps.';
  }

  String _buildUncertainImageResponse(
    String userMessage, {
    required String hintCropType,
  }) {
    final topGuess = _extractTopGuessFromPrompt(userMessage);
    final cropLabel = hintCropType.isNotEmpty ? hintCropType : 'the selected crop';

    if (topGuess != null) {
      return 'I could not confidently confirm $cropLabel from this image offline.\n\n'
          'Top offline guess: ${topGuess.label} (${topGuess.confidenceLabel}).\n\n'
          'Please try one of these next steps:\n'
          '1. Retake the photo with a closer, sharper view of the affected area\n'
          '2. Capture the front and back of the leaf in good lighting\n'
          '3. Go online for a more comprehensive AI review\n\n'
          'I will avoid guessing a disease or showing a treatment plan until the crop can be identified more reliably.';
    }

    return 'I could not confidently confirm a diagnosis from this image offline.\n\n'
        'Please try one of these next steps:\n'
        '1. Retake the photo with a closer, sharper view of the affected area\n'
        '2. Capture the front and back of the leaf in good lighting\n'
        '3. If you are online, try again for a more comprehensive AI review\n\n'
        'I will avoid guessing a disease or treatment until the model can identify the crop more reliably.';
  }

  _OfflineTopGuess? _extractTopGuessFromPrompt(String text) {
    final match = RegExp(
      r'Top offline guess:\s*([^\n]+?)\s+at\s+(\d{1,3})% confidence',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) {
      return null;
    }

    final label = (match.group(1) ?? '').trim();
    final confidence = (match.group(2) ?? '').trim();
    if (label.isEmpty || confidence.isEmpty) {
      return null;
    }

    return _OfflineTopGuess(
      label: label,
      confidenceLabel: '$confidence% confidence',
    );
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
      for (final step in [
        ...?knowledge.treatmentSteps,
        ...?knowledge.preventionSteps
      ]) {
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
        ? exampleSteps
            .asMap()
            .entries
            .map((entry) => '${entry.key + 1}. ${entry.value}')
            .join('\n')
        : 'Tell me the product name or active ingredient and I will compare it against the offline crop guidance I have for $cropType.';

    return 'I can still help with fertilizers and crop products for your $cropType crop offline.\n\n'
      'Share the product name, fertilizer grade, or active ingredient and I will compare it against the crop guidance I already have.\n\n'
      'Examples from my $cropType knowledge base:\n$examplesText\n\n'
      'Please still verify the label, dosage, and pre-harvest interval before applying it.';
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

  bool _requiresFreshImageForMessage(
    String text, {
    required String? resolvedHintCropType,
  }) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) {
      return false;
    }

    if (_looksLikeObservationSentence(lower) ||
        _looksLikeDiagnosisRequest(lower)) {
      return true;
    }

    if (_looksLikeCurrentCropConcern(lower)) {
      return true;
    }

    if (resolvedHintCropType != null && resolvedHintCropType.isNotEmpty) {
      return false;
    }

    return false;
  }

  bool _looksLikeDiagnosisRequest(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) {
      return false;
    }

    const diagnosisPhrases = [
      'what disease',
      'what pest',
      'what is wrong',
      'what\'s wrong',
      'diagnose',
      'diagnosis',
      'identify this',
      'identify the disease',
      'analyze this',
      'analyse this',
      'check this crop',
      'check this plant',
      'is this diseased',
      'does this have',
    ];

    return diagnosisPhrases.any(lower.contains);
  }

  bool _looksLikeCurrentCropConcern(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) {
      return false;
    }

    const cropReferences = [
      'this crop',
      'this plant',
      'this leaf',
      'these leaves',
      'my crop',
      'my plant',
      'my leaves',
      'my leaf',
      'our crop',
      'current crop',
    ];

    const symptomHints = [
      'spot',
      'yellow',
      'brown',
      'black',
      'curl',
      'wilt',
      'wilting',
      'rot',
      'hole',
      'pest',
      'bug',
      'mold',
      'mould',
      'blight',
      'mildew',
      'lesion',
      'disease',
      'infect',
      'damage',
      'symptom',
      'drying',
      'drooping',
    ];

    final refersToCurrentCrop = cropReferences.any(lower.contains);
    if (!refersToCurrentCrop) {
      return false;
    }

    return symptomHints.any(lower.contains);
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

  Future<void> _touchCurrentSession({
    required DateTime activityAt,
    String? preferredTitle,
  }) async {
    final current = _currentSession;
    if (current == null) {
      return;
    }

    final updated = current.copyWith(
      title: preferredTitle?.trim().isNotEmpty == true
          ? preferredTitle!.trim()
          : current.title,
      lastMessageAt: activityAt,
      updatedAt: activityAt,
    );
    _currentSession = updated;

    final hasVisibleInput = _hasVisibleUserInput(_currentMessages);
    final existingIndex = _sessions.indexWhere((session) => session.id == updated.id);
    if (existingIndex != -1) {
      _sessions.removeAt(existingIndex);
    }
    if (hasVisibleInput) {
      _sessions.insert(0, updated);
    }

    try {
      await _supabase.upsertChatSession(_sessionRemoteMap(updated));
    } catch (_) {}
    await _db.upsertRow(AppConstants.chatSessionsTable, updated.toMap());
  }

  Future<List<ChatSessionModel>> _filterHistorySessions(
    List<ChatSessionModel> sessions,
  ) async {
    final filtered = <ChatSessionModel>[];

    for (final session in sessions) {
      final localRows = await _db.queryChatMessages(session.id);
      var messages = localRows.map(ChatMessageModel.fromMap).toList();

      if (!_hasVisibleUserInput(messages)) {
        try {
          final remoteRows = await _supabase.getChatMessages(session.id);
          if (remoteRows.isNotEmpty) {
            messages = remoteRows.map(ChatMessageModel.fromMap).toList();
            await _db.upsertRows(
              AppConstants.chatMessagesTable,
              messages.map((message) => message.toMap()),
            );
          }
        } catch (_) {
          // Keep the local snapshot when remote history is unavailable.
        }
      }

      if (_hasVisibleUserInput(messages)) {
        filtered.add(session);
      }
    }

    filtered.sort(
      (a, b) => (b.lastMessageAt ?? b.createdAt)
          .compareTo(a.lastMessageAt ?? a.createdAt),
    );
    return filtered;
  }

  bool _hasVisibleUserInput(List<ChatMessageModel> messages) {
    for (final message in messages) {
      if (message.role != MessageRole.user) {
        continue;
      }
      if (message.content.trim().isEmpty) {
        continue;
      }
      if (message.metadata?['hide_text'] == true) {
        continue;
      }
      return true;
    }
    return false;
  }

  String _buildConversationTitle({
    required String userContent,
    required bool hideMessageTextInUi,
    required DiagnosisModel? attachedDiagnosis,
    required Map<String, dynamic>? aiMetadata,
    required String? hintCropType,
  }) {
    final diseaseName =
        (aiMetadata?['disease_name'] as String? ?? attachedDiagnosis?.diseaseName ?? '')
            .trim();
    final cropType =
        (aiMetadata?['crop_type'] as String? ?? hintCropType ?? '')
            .trim()
            .toLowerCase();

    if (diseaseName.isNotEmpty && cropType.isNotEmpty) {
      final cropLabel = _titleCaseWords(cropType);
      final diseaseLabel = humanizeDiseaseLabel(diseaseName);
      if (diseaseLabel.toLowerCase().contains('healthy')) {
        return '$cropLabel healthy check';
      }
      return '$cropLabel $diseaseLabel';
    }

    if (diseaseName.isNotEmpty) {
      return humanizeDiseaseLabel(diseaseName);
    }

    if (cropType.isNotEmpty) {
      return '${_titleCaseWords(cropType)} diagnosis';
    }

    if (!hideMessageTextInUi && userContent.trim().isNotEmpty) {
      return _summarizeTitleFromText(userContent);
    }

    return 'Crop consultation';
  }

  String _summarizeTitleFromText(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^A-Za-z0-9\s]'), '');
    if (normalized.isEmpty) {
      return 'Crop consultation';
    }

    final words = normalized.split(' ').where((word) => word.isNotEmpty).toList();
    final summary = words.take(6).join(' ');
    return _titleCaseWords(summary);
  }

  String _titleCaseWords(String value) {
    return value
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
        .join(' ');
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

    // Check knowledge base first (exact substring match).
    for (final knowledge in _knowledgeBase) {
      final diseaseName = knowledge.diseaseName.trim();
      if (diseaseName.isNotEmpty &&
          normalized.contains(diseaseName.toLowerCase())) {
        return diseaseName;
      }
    }

    // Keyword-based fallback: all significant words in the disease name must
    // appear somewhere in the response (handles "powdery mildew" matching
    // "Squash Powdery Mildew" when the crop context is already known).
    for (final knowledge in _knowledgeBase) {
      final diseaseName = knowledge.diseaseName.trim();
      if (diseaseName.isEmpty) continue;
      final keywords = diseaseName
          .toLowerCase()
          .split(RegExp(r'[\s_\-]+'))
          .where((w) => w.length > 3)
          .toList();
      if (keywords.length >= 2 && keywords.every(normalized.contains)) {
        return diseaseName;
      }
    }

    final flattened = aiContent.replaceAll('\n', ' ');
    final patterns = [
      RegExp(
        r'(?:diagnosis|assessment|condition)\s*[:\-]\s*([A-Za-z][A-Za-z\s\-/]{2,60})',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:likely|appears to have|appears to be|shows signs of|consistent with|suggests|affected by)\s+([A-Za-z][A-Za-z\s\-/]{2,60})',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(flattened);
      if (match == null) {
        continue;
      }
      final candidate = _sanitizeInferredDiseaseName(match.group(1) ?? '');
      if (candidate.isNotEmpty) {
        return candidate;
      }
    }

    // Only classify as Healthy when no specific disease was found AND the
    // response genuinely describes a healthy crop — preventing phrases like
    // "the rest of the plant appears healthy" from overriding a disease name.
    if (_looksHealthyAnswer(normalized)) {
      return 'Healthy';
    }

    return '';
  }

  bool _looksHealthyAnswer(String text) {
    const healthyPhrases = [
      'looks healthy',
      'appears healthy',
      'seems healthy',
      'is healthy',
      'healthy crop',
      'healthy plant',
      'no obvious disease',
      'no visible disease',
      'no clear disease',
      'no signs of disease',
      'no strong signs of disease',
    ];

    return healthyPhrases.any(text.contains);
  }

  String _sanitizeInferredDiseaseName(String raw) {
    var value = raw.trim();
    if (value.isEmpty) {
      return '';
    }

    value = value.replaceAll(RegExp(r'[\.,;:!?].*$'), '').trim();
    value = value.replaceAll(
      RegExp(
        r'\b(on|in|with|because|from|caused by|which|that|for)\b.*$',
        caseSensitive: false,
      ),
      '',
    ).trim();
    value = value.replaceAll(RegExp(r'\s+'), ' ');

    if (value.length < 3 || value.split(' ').length > 6) {
      return '';
    }

    return _titleCaseWords(value);
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

    if (_isHealthyDiagnosisName(inferredDiseaseName) &&
        _supportedTreatmentCardCrops.contains(inferredCropType)) {
      return _healthyDailyPlanForCrop(inferredCropType);
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

  List<String> _resolveRecommendedActions({
    required List<String> recommendedActions,
    required String inferredDiseaseName,
    required String inferredCropType,
    bool allowHealthyFallback = true,
  }) {
    final deduped = <String>[];
    for (final action in recommendedActions) {
      final normalized = action.trim();
      if (normalized.isNotEmpty && !deduped.contains(normalized)) {
        deduped.add(normalized);
      }
    }

    if (deduped.isNotEmpty) {
      return deduped.take(7).toList();
    }

    if (allowHealthyFallback &&
        _isHealthyDiagnosisName(inferredDiseaseName) &&
        _supportedTreatmentCardCrops.contains(inferredCropType)) {
      return _healthyDailyPlanForCrop(inferredCropType);
    }

    return const [];
  }

  List<String> _healthyDailyPlanForCrop(String cropType) {
    switch (cropType.trim().toLowerCase()) {
      case 'tomato':
        return const [
          'Day 1: Water at the base and keep the stems supported on stakes or a trellis.',
          'Day 2: Inspect the leaves for early blight spots, wilting, or pest damage.',
          'Day 3: Feed with balanced fertilizer, or shift to a higher-potassium feed once fruiting starts.',
          'Day 4: Remove weeds and keep lower leaves away from wet soil to maintain airflow.',
        ];
      case 'pepper':
        return const [
          'Day 1: Water at the base and keep the soil evenly moist.',
          'Day 2: Check leaves and young shoots for thrips, aphids, and fresh spots.',
          'Day 3: Check flowers and fruits for blossom-end rot and apply calcium-magnesium feed only if needed.',
          'Day 4: Remove weeds and keep the plant area open so air can move through the canopy.',
        ];
      case 'eggplant':
        return const [
          'Day 1: Keep the soil evenly moist without waterlogging the roots.',
          'Day 2: Inspect leaf undersides for mites, aphids, and thrips.',
          'Day 3: Apply balanced fertilizer only on the planned feeding day during fruiting.',
          'Day 4: Remove damaged leaves and keep the bed clean to reduce pest pressure.',
        ];
      case 'squash':
        return const [
          'Day 1: Water at the base early so the leaves dry quickly.',
          'Day 2: Check the leaves for powdery patches, pests, or sudden yellowing.',
          'Day 3: Keep vines open and avoid excess nitrogen that pushes overly lush growth.',
          'Day 4: Remove weak or heavily shaded leaves to improve airflow around the plant.',
        ];
      case 'pechay':
        return const [
          'Day 1: Water lightly at the base and avoid splashing soil onto the leaves.',
          'Day 2: Check leaves for chewing pests, aphids, or soft rot.',
          'Day 3: Apply a light balanced fertilizer only on the planned feeding day.',
          'Day 4: Keep the bed weed-free and remove damaged outer leaves early.',
        ];
      default:
        return const [
          'Day 1: Water at the base and keep the soil evenly moist.',
          'Day 2: Inspect leaves for pests, new spots, or sudden wilting.',
          'Day 3: Keep weeds down and maintain good airflow around the crop.',
        ];
    }
  }

  String _planTitleForDiagnosis(String inferredDiseaseName) {
    return _isHealthyDiagnosisName(inferredDiseaseName)
        ? 'Daily Care Plan'
        : 'Treatment Steps';
  }

  Severity _resolveConversationSeverity({
    required DiagnosisModel? attachedDiagnosis,
    required String inferredDiseaseName,
    required String aiContent,
  }) {
    if (_isHealthyDiagnosisName(inferredDiseaseName)) {
      return Severity.healthy;
    }

    if (attachedDiagnosis != null) {
      return attachedDiagnosis.severity;
    }

    return _inferSeverityFromContent(aiContent) ?? Severity.moderate;
  }

  Severity? _inferSeverityFromContent(String aiContent) {
    final normalized = aiContent.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    const severeHints = [
      'severe',
      'serious',
      'advanced',
      'badly infected',
      'heavily infected',
      'rapidly spreading',
      'high risk',
      'urgent',
    ];
    if (severeHints.any(normalized.contains)) {
      return Severity.severe;
    }

    const mildHints = [
      'mild',
      'minor',
      'early stage',
      'slight',
      'small amount',
      'limited spots',
      'light infection',
      'starting to',
      'early signs',
    ];
    if (mildHints.any(normalized.contains)) {
      return Severity.mild;
    }

    const moderateHints = [
      'moderate',
      'spreading',
      'noticeable',
      'several leaves',
      'visible damage',
    ];
    if (moderateHints.any(normalized.contains)) {
      return Severity.moderate;
    }

    return null;
  }

  bool _isHealthyDiagnosisName(String value) {
    return value.trim().toLowerCase().contains('healthy');
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

      final cropType =
          (metadata['crop_type'] as String? ?? '').trim().toLowerCase();
      if (cropType.isNotEmpty) {
        return cropType;
      }
    }

    return null;
  }
}

class _OfflineTopGuess {
  final String label;
  final String confidenceLabel;

  const _OfflineTopGuess({
    required this.label,
    required this.confidenceLabel,
  });
}
