import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_enums.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../data/models/chat_session_model.dart';
import '../../../data/models/diagnosis_model.dart';
import '../../../data/remote/ai_backend_service.dart';
import '../../../data/models/disease_knowledge_model.dart';
import '../../../data/remote/supabase_service.dart';

class ChatProvider extends ChangeNotifier {
  final SupabaseService _supabase;
  final DatabaseHelper _db;
  final AiBackendService _aiBackend;

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
  })  : _supabase = supabase,
        _db = db,
        _aiBackend = aiBackend;

  List<ChatSessionModel> get sessions => _sessions;
  List<ChatMessageModel> get currentMessages => _currentMessages;
  ChatSessionModel? get currentSession => _currentSession;
  bool get isLoading => _isLoading;
  bool get isTyping => _isTyping;

  // ─── Init ─────────────────────────────────────────────────────────────────

  Future<void> loadKnowledgeBase() async {
    try {
      final rows = await _supabase.getDiseaseKnowledge();
      _knowledgeBase = rows.map(DiseaseKnowledgeModel.fromMap).toList();
      await _db.upsertRows(
        AppConstants.diseaseKnowledgeTable,
        _knowledgeBase.map((knowledge) => knowledge.toMap()),
      );
    } catch (_) {
      final rows = await _db.queryDiseaseKnowledge('');
      if (rows.isNotEmpty) {
        _knowledgeBase = rows.map(DiseaseKnowledgeModel.fromMap).toList();
      }
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
          final res = await http.get(Uri.parse(url))
              .timeout(const Duration(seconds: 15));
          if (res.statusCode == 200) {
            _currentMessages[i] = _currentMessages[i]
                .copyWith(imageBytes: res.bodyBytes);
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
  }) async {
    if (_currentSession == null) {
      await startNewSession(userId);
    }

    // Upload image to Supabase Storage so it survives history loads
    final msgId = const Uuid().v4();
    String? uploadedImageUrl;
    if (attachedImageBytes != null && attachedImageBytes.isNotEmpty) {
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
      metadata: uploadedImageUrl != null
          ? {'image_url': uploadedImageUrl}
          : null,
      imageBytes: attachedImageBytes != null
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

    try {
      final backendResponse = await _aiBackend.sendChatMessage(
        userMessage: content,
        cropId: attachedDiagnosis?.cropId.isNotEmpty == true
            ? attachedDiagnosis!.cropId
            : _currentSession?.cropId,
        diagnosis: attachedDiagnosis,
        imageBytes: attachedImageBytes,
        imageMimeType: attachedImageMimeType,
      );
      // Store recommended_actions in metadata but DON'T append them to text
      // — they are rendered as an interactive checklist in the UI.
      aiContent = _formatBackendResponse(backendResponse);
      aiMetadata = {
        'model': backendResponse.model,
        'sources': backendResponse.sources,
        'recommended_actions': backendResponse.recommendedActions,
        'warnings': backendResponse.warnings,
      };
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 500));
      aiContent = _buildAIResponse(
        content,
        attachedDiagnosis: attachedDiagnosis,
      );
      aiMetadata = {'model': 'local-fallback'};
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
    final hasActions =
        (aiMetadata['recommended_actions'] as List<dynamic>? ?? []).isNotEmpty;
    final hasImage =
        attachedImageBytes != null && attachedImageBytes.isNotEmpty;
    if (attachedDiagnosis != null || (hasImage && hasActions)) {
      final inferredDiseaseName =
          (attachedDiagnosis?.diseaseName.trim().isNotEmpty ?? false)
              ? attachedDiagnosis!.diseaseName.trim()
              : _inferDiseaseName(aiContent);
      final inferredCropType = _inferCropType(
        labelKey: attachedDiagnosis?.labelKey,
        diseaseName: inferredDiseaseName,
        aiContent: aiContent,
      );
      final inferredLabelKey =
          (attachedDiagnosis?.labelKey?.trim().isNotEmpty ?? false)
              ? attachedDiagnosis!.labelKey!.trim()
              : _inferLabelKey(
                  diseaseName: inferredDiseaseName,
                  cropType: inferredCropType,
                );
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

  // ─── AI Response Builder ─────────────────────────────────────────────────

  String _buildAIResponse(String userMessage,
      {DiagnosisModel? attachedDiagnosis}) {
    final lower = userMessage.toLowerCase();

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
    final buffer = StringBuffer(response.answer.trim());

    // recommended_actions are NOT appended here — they render as a checklist
    // widget in _MessageBubble via metadata['recommended_actions'].

    if (response.warnings.isNotEmpty) {
      buffer
        ..write('\n\nWarnings:\n')
        ..writeAll(
          response.warnings.map((warning) => '• $warning'),
          '\n',
        );
    }

    if (response.sources.isNotEmpty) {
      buffer.write('\n\nSources: ${response.sources.join(', ')}');
    }

    return buffer.toString().trim();
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
    }.entries) {
      for (final kw in entry.value) {
        if (lk.contains(kw) || dn.contains(kw) || ai.contains(kw)) {
          return entry.key;
        }
      }
    }
    return 'tomato'; // fallback
  }
}
