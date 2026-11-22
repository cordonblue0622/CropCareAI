import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../core/constants/app_enums.dart';
import '../models/ai_backend_models.dart';
import '../models/diagnosis_model.dart';
import 'supabase_service.dart';

export '../models/ai_backend_models.dart';

class AiBackendService {
  static const Duration _warmUpCacheDuration = Duration(minutes: 3);

  final SupabaseService _supabase;
  final http.Client _client;

  Future<void>? _warmUpInFlight;
  DateTime? _lastWarmUpAt;

  AiBackendService({
    required SupabaseService supabase,
    http.Client? client,
  })  : _supabase = supabase,
        _client = client ?? http.Client();

  String get baseUrl {
    return resolveBaseUrl(
      configuredBaseUrl: AppConstants.aiBackendBaseUrl,
      configuredAndroidBaseUrl: AppConstants.aiBackendAndroidBaseUrl,
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    );
  }

  static String resolveBaseUrl({
    required String configuredBaseUrl,
    required String configuredAndroidBaseUrl,
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    final configured = _sanitizeConfiguredBaseUrl(configuredBaseUrl);
    if (configured.isNotEmpty) {
      return _withoutTrailingSlash(configured);
    }

    if (isWeb) {
      return 'http://127.0.0.1:8000';
    }

    switch (platform) {
      case TargetPlatform.android:
        final androidConfigured =
            _sanitizeConfiguredBaseUrl(configuredAndroidBaseUrl);
        if (androidConfigured.isNotEmpty) {
          return _withoutTrailingSlash(androidConfigured);
        }
        return 'http://10.0.2.2:8000';
      default:
        return 'http://127.0.0.1:8000';
    }
  }

  static String _withoutTrailingSlash(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  static String _sanitizeConfiguredBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    var sanitized = trimmed;
    while (sanitized.startsWith('"') || sanitized.startsWith("'")) {
      sanitized = sanitized.substring(1).trimLeft();
    }
    while (sanitized.endsWith('"') || sanitized.endsWith("'")) {
      sanitized = sanitized.substring(0, sanitized.length - 1).trimRight();
    }
    return sanitized;
  }

  Future<void> warmUpIfNeeded({bool force = false}) async {
    if (!_shouldWarmUpHostedBackend()) {
      return;
    }

    final now = DateTime.now();
    if (!force &&
        _lastWarmUpAt != null &&
        now.difference(_lastWarmUpAt!) < _warmUpCacheDuration) {
      return;
    }

    if (_warmUpInFlight != null) {
      await _warmUpInFlight;
      return;
    }

    final future = _performWarmUp();
    _warmUpInFlight = future;
    try {
      await future;
    } finally {
      _warmUpInFlight = null;
    }
  }

  Future<AiBackendChatResponse> sendChatMessage({
    required String userMessage,
    String? cropId,
    DiagnosisModel? diagnosis,
    List<int>? imageBytes,
    List<List<int>> imageBytesList = const [],
    String? imageMimeType,
    List<Map<String, String>> conversationHistory = const [],
    String? locale,
    String? hintCropType,
    bool imagesFromPreviousTurns = false,
  }) async {
    if (imageBytesList.any((bytes) => bytes.isEmpty)) {
      throw ArgumentError(
          'An attached photo is empty. Please select it again.');
    }
    final imageDataUrls = imageBytesList
        .where((bytes) => bytes.isNotEmpty)
        .map((bytes) => _buildImageDataUrl(bytes, mimeType: imageMimeType))
        .toList(growable: false);
    final payload = {
      'user_message': userMessage,
      if (cropId != null && cropId.isNotEmpty) 'crop_id': cropId,
      if (diagnosis != null)
        'diagnosis': {
          'crop_type': _inferDiagnosisCropType(diagnosis),
          'label_key': diagnosis.labelKey,
          'disease_name': diagnosis.diseaseName,
          'confidence': diagnosis.confidenceScore,
          'severity': diagnosis.severity.value,
        },
      if (imageDataUrls.isEmpty && imageBytes != null && imageBytes.isNotEmpty)
        'image_data_url': _buildImageDataUrl(
          imageBytes,
          mimeType: imageMimeType,
        ),
      if (imageDataUrls.isNotEmpty) 'image_data_urls': imageDataUrls,
      if (imagesFromPreviousTurns && imageDataUrls.isNotEmpty)
        'images_from_previous_turns': true,
      if (conversationHistory.isNotEmpty)
        'conversation_history': conversationHistory,
      if (locale != null && locale.isNotEmpty) 'locale': locale,
      if (hintCropType != null && hintCropType.trim().isNotEmpty)
        'hint_crop_type': hintCropType.trim().toLowerCase(),
    };
    final response = await _postJsonWithWarmup(
      path: '/v1/chat',
      payload: payload,
      timeout: const Duration(seconds: 120),
    );

    _throwIfError(response);

    return AiBackendChatResponse.fromMap(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteAccount() async {
    await warmUpIfNeeded();
    final response = await _client
        .delete(
          Uri.parse('$baseUrl/v1/account'),
          headers: _headers(),
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode == 204) return;

    var message = 'Your account could not be deleted. Please try again.';
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = decoded['detail'];
      if (detail is String && detail.trim().isNotEmpty) message = detail.trim();
    } catch (_) {}
    throw AiBackendHttpException(
      statusCode: response.statusCode,
      message: message,
    );
  }

  Future<AiBackendDetectResponse> detectImage({
    required List<int> imageBytes,
    required String filename,
    String? cropType,
  }) async {
    final response = await _sendMultipartWithWarmup(
      path: '/v1/detect',
      timeout: const Duration(seconds: 45),
      buildRequest: () {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/v1/detect'),
        )
          ..headers.addAll(_headers())
          ..files.add(
            http.MultipartFile.fromBytes(
              'image',
              imageBytes,
              filename: filename,
            ),
          );

        if (cropType != null && cropType.isNotEmpty) {
          request.fields['crop_type'] = cropType;
        }
        return request;
      },
    );

    _throwIfError(response);

    return AiBackendDetectResponse.fromMap(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AiBackendTranscribeResponse> transcribeAudio({
    required List<int> audioBytes,
    required String filename,
  }) async {
    final response = await _sendMultipartWithWarmup(
      path: '/v1/transcribe',
      timeout: const Duration(seconds: 60),
      buildRequest: () => http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/v1/transcribe'),
      )
        ..headers.addAll(_headers())
        ..files.add(
          http.MultipartFile.fromBytes(
            'audio',
            audioBytes,
            filename: filename,
          ),
        ),
    );

    _throwIfError(response);

    return AiBackendTranscribeResponse.fromMap(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AiBackendProgressResponse> assessCropHealth({
    required String cropType,
    required String diseaseName,
    int daysSinceTreatment = 0,
    List<int>? imageBytes,
    String? imageMimeType,
    String? imageDataUrl,
    String? previousImageReference,
    String? previousAssessment,
    String? previousProgressStatus,
    String? previousUpdateDate,
    List<String> completedTasks = const [],
    String? note,
    double? currentHealthScore,
  }) async {
    final response = await _postJsonWithWarmup(
      path: '/v1/progress',
      payload: {
        'crop_type': cropType,
        'disease_name': diseaseName,
        'days_since_treatment': daysSinceTreatment,
        if (imageDataUrl != null && imageDataUrl.isNotEmpty)
          'image_data_url': imageDataUrl
        else if (imageBytes != null && imageBytes.isNotEmpty)
          'image_data_url':
              _buildImageDataUrl(imageBytes, mimeType: imageMimeType),
        if (previousImageReference != null && previousImageReference.isNotEmpty)
          'previous_image_reference': previousImageReference,
        if (previousAssessment != null && previousAssessment.isNotEmpty)
          'previous_assessment': previousAssessment,
        if (previousProgressStatus != null && previousProgressStatus.isNotEmpty)
          'previous_progress_status': previousProgressStatus,
        if (previousUpdateDate != null && previousUpdateDate.isNotEmpty)
          'previous_update_date': previousUpdateDate,
        'completed_tasks': completedTasks,
        if (note != null && note.isNotEmpty) 'note': note,
        if (currentHealthScore != null)
          'current_health_score': currentHealthScore,
      },
      timeout: const Duration(seconds: 75),
    );

    _throwIfError(response);
    return AiBackendProgressResponse.fromMap(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<AiBackendChatResponse> suggestTreatmentExtension({
    required String cropType,
    required String cropName,
    required String diseaseName,
    required double currentHealthScore,
    required ProgressStatus progressStatus,
    String? latestNote,
  }) {
    final note = latestNote?.trim();
    final prompt = StringBuffer()
      ..writeln(
        'A farmer has completed the current treatment timeline for a $cropType crop named "$cropName" diagnosed with $diseaseName.',
      )
      ..writeln(
        'The latest health score is ${currentHealthScore.toStringAsFixed(0)} out of 100 and the trend is ${progressStatus.value}.',
      )
      ..writeln(
        'Search for reputable agricultural, university, or government-backed remedies or follow-up actions that could help this crop recover further.',
      )
      ..writeln(
        'Respond with a short explanation, 3 to 6 concrete recommended actions, and populate the sources field with the legit sources you used.',
      )
      ..writeln(
        'If the crop needs expert inspection, say so clearly and keep the advice focused on safe next steps.',
      );

    if (note != null && note.isNotEmpty) {
      prompt
        ..writeln()
        ..writeln('Latest farmer update: $note');
    }

    return sendChatMessage(
      userMessage: prompt.toString(),
      hintCropType: cropType,
    );
  }

  Future<http.Response> _postJsonWithWarmup({
    required String path,
    required Object payload,
    required Duration timeout,
  }) async {
    final allowWarmupRetry = path != '/v1/chat' && path != '/v1/progress';
    if (allowWarmupRetry) await warmUpIfNeeded();
    final encodedPayload = jsonEncode(payload);
    var response = await _client
        .post(
          Uri.parse('$baseUrl$path'),
          headers: _headers(json: true),
          body: encodedPayload,
        )
        .timeout(timeout);

    if (allowWarmupRetry && _isRetryableStatusCode(response.statusCode)) {
      await warmUpIfNeeded(force: true);
      response = await _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: _headers(json: true),
            body: encodedPayload,
          )
          .timeout(timeout);
    }

    return response;
  }

  Future<http.Response> _sendMultipartWithWarmup({
    required String path,
    required Duration timeout,
    required http.MultipartRequest Function() buildRequest,
  }) async {
    if (path != '/v1/transcribe') await warmUpIfNeeded();

    var request = buildRequest();
    var streamed = await request.send().timeout(timeout);
    var response = await http.Response.fromStream(streamed).timeout(timeout);

    if (path != '/v1/transcribe' &&
        _isRetryableStatusCode(response.statusCode)) {
      await warmUpIfNeeded(force: true);
      request = buildRequest();
      streamed = await request.send().timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    }

    return response;
  }

  Future<void> _performWarmUp() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'), headers: _headers())
          .timeout(const Duration(seconds: 45));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _lastWarmUpAt = DateTime.now();
        return;
      }
    } catch (_) {
      // Fall through to the root endpoint.
    }

    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/'), headers: _headers())
          .timeout(const Duration(seconds: 45));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _lastWarmUpAt = DateTime.now();
      }
    } catch (_) {
      // Best effort only — actual requests may still succeed.
    }
  }

  bool _shouldWarmUpHostedBackend() {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return uri.scheme == 'https' &&
        host.isNotEmpty &&
        host != '127.0.0.1' &&
        host != 'localhost' &&
        host != '10.0.2.2';
  }

  bool _isRetryableStatusCode(int statusCode) {
    return statusCode == 408 ||
        statusCode == 425 ||
        statusCode == 429 ||
        statusCode == 500 ||
        statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504;
  }

  Map<String, String> _headers({bool json = false}) {
    final accessToken = _supabase.currentSession?.accessToken;
    return {
      'accept': 'application/json',
      if (json) 'content-type': 'application/json',
      if (accessToken != null && accessToken.isNotEmpty)
        'authorization': 'Bearer $accessToken',
    };
  }

  String _buildImageDataUrl(List<int> imageBytes, {String? mimeType}) {
    final normalizedMimeType = (mimeType != null && mimeType.trim().isNotEmpty)
        ? mimeType.trim()
        : 'image/jpeg';
    return 'data:$normalizedMimeType;base64,${base64Encode(imageBytes)}';
  }

  String _inferDiagnosisCropType(DiagnosisModel diagnosis) {
    final normalized =
        '${diagnosis.labelKey ?? ''} ${diagnosis.diseaseName}'.toLowerCase();
    for (final entry in const {
      'tomato': ['tomato'],
      'eggplant': ['eggplant', 'talong'],
      'pepper': ['pepper', 'capsicum'],
      'pechay': ['pechay', 'bok choy', 'bokchoy'],
      'squash': ['squash', 'kalabasa'],
      'corn': ['corn', 'maize'],
    }.entries) {
      if (entry.value.any(normalized.contains)) {
        return entry.key;
      }
    }
    return '';
  }

  void _throwIfError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    String? detail;
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rawDetail = decoded['detail'];
      if (rawDetail is String && rawDetail.trim().isNotEmpty) {
        detail = rawDetail.trim();
      }
    } catch (_) {
      // Non-JSON errors use the response body below.
    }
    if (detail != null) {
      throw AiBackendHttpException(
          statusCode: response.statusCode, message: detail);
    }

    final body = response.body.trim();
    throw AiBackendHttpException(
      statusCode: response.statusCode,
      message: body.isEmpty
          ? 'AI backend request failed with status ${response.statusCode}.'
          : body,
    );
  }
}

class AiBackendHttpException implements Exception {
  final int statusCode;
  final String message;

  const AiBackendHttpException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() => message;
}

class AiBackendChatResponse {
  final String answer;
  final List<String> recommendedActions;
  final List<String> warnings;
  final List<String> sources;
  final String model;
  final bool inAppCropScope;
  final bool showTreatmentUi;
  final String verifiedCrop;
  final String verifiedDisease;

  const AiBackendChatResponse({
    required this.answer,
    required this.recommendedActions,
    required this.warnings,
    required this.sources,
    required this.model,
    this.inAppCropScope = true,
    this.showTreatmentUi = false,
    this.verifiedCrop = '',
    this.verifiedDisease = '',
  });

  factory AiBackendChatResponse.fromMap(Map<String, dynamic> map) {
    List<String> parseList(String key) {
      final raw = map[key];
      if (raw is List) {
        return raw.map((item) => item.toString()).toList();
      }
      return const [];
    }

    final scopeRaw = map['in_app_crop_scope'];
    final showRaw = map['show_treatment_ui'];

    return AiBackendChatResponse(
      answer: (map['answer'] as String? ?? '').trim(),
      recommendedActions: parseList('recommended_actions'),
      warnings: parseList('warnings'),
      sources: parseList('sources'),
      model: (map['model'] as String? ?? 'backend').trim(),
      inAppCropScope: scopeRaw is bool ? scopeRaw : true,
      showTreatmentUi: showRaw is bool ? showRaw : false,
      verifiedCrop: (map['verified_crop'] as String? ?? '').trim(),
      verifiedDisease: (map['verified_disease'] as String? ?? '').trim(),
    );
  }
}

class AiBackendTranscribeResponse {
  final String transcript;
  final String language;
  final String source;
  final List<String> notes;

  const AiBackendTranscribeResponse({
    required this.transcript,
    required this.language,
    required this.source,
    required this.notes,
  });

  factory AiBackendTranscribeResponse.fromMap(Map<String, dynamic> map) {
    List<String> parseList(String key) {
      final raw = map[key];
      if (raw is List) {
        return raw.map((item) => item.toString()).toList();
      }
      return const [];
    }

    return AiBackendTranscribeResponse(
      transcript: (map['transcript'] as String? ?? '').trim(),
      language: (map['language'] as String? ?? '').trim(),
      source: (map['source'] as String? ?? '').trim(),
      notes: parseList('notes'),
    );
  }
}
