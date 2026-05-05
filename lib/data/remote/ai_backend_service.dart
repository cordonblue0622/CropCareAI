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
  final SupabaseService _supabase;
  final http.Client _client;

  AiBackendService({
    required SupabaseService supabase,
    http.Client? client,
  })  : _supabase = supabase,
        _client = client ?? http.Client();

  String get baseUrl {
    final configured = AppConstants.aiBackendBaseUrl.trim();
    if (configured.isNotEmpty) {
      return configured.endsWith('/')
          ? configured.substring(0, configured.length - 1)
          : configured;
    }

    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000';
      default:
        return 'http://127.0.0.1:8000';
    }
  }

  Future<AiBackendChatResponse> sendChatMessage({
    required String userMessage,
    String? cropId,
    DiagnosisModel? diagnosis,
    List<int>? imageBytes,
    String? imageMimeType,
    String? locale,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/v1/chat'),
          headers: _headers(json: true),
          body: jsonEncode({
            'user_message': userMessage,
            if (cropId != null && cropId.isNotEmpty) 'crop_id': cropId,
            if (diagnosis != null)
              'diagnosis': {
                'label_key': diagnosis.labelKey,
                'disease_name': diagnosis.diseaseName,
                'confidence': diagnosis.confidenceScore,
                'severity': diagnosis.severity.value,
              },
            if (imageBytes != null && imageBytes.isNotEmpty)
              'image_data_url': _buildImageDataUrl(
                imageBytes,
                mimeType: imageMimeType,
              ),
            if (locale != null && locale.isNotEmpty) 'locale': locale,
          }),
        )
        .timeout(const Duration(seconds: 20));

    _throwIfError(response);

    return AiBackendChatResponse.fromMap(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AiBackendDetectResponse> detectImage({
    required List<int> imageBytes,
    required String filename,
    String? cropType,
  }) async {
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

    final streamed = await request.send().timeout(const Duration(seconds: 45));
    final response = await http.Response.fromStream(streamed);

    _throwIfError(response);

    return AiBackendDetectResponse.fromMap(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AiBackendTranscribeResponse> transcribeAudio({
    required List<int> audioBytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
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
      );

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);

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
    List<String> completedTasks = const [],
    String? note,
    double? currentHealthScore,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/v1/progress'),
          headers: _headers(json: true),
          body: jsonEncode({
            'crop_type': cropType,
            'disease_name': diseaseName,
            'days_since_treatment': daysSinceTreatment,
            if (imageBytes != null && imageBytes.isNotEmpty)
              'image_data_url': _buildImageDataUrl(imageBytes,
                  mimeType: imageMimeType),
            'completed_tasks': completedTasks,
            if (note != null && note.isNotEmpty) 'note': note,
            if (currentHealthScore != null)
              'current_health_score': currentHealthScore,
          }),
        )
        .timeout(const Duration(seconds: 45));

    _throwIfError(response);
    return AiBackendProgressResponse.fromMap(
        jsonDecode(response.body) as Map<String, dynamic>);
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
    final normalizedMimeType =
        (mimeType != null && mimeType.trim().isNotEmpty) ? mimeType.trim() : 'image/jpeg';
    return 'data:$normalizedMimeType;base64,${base64Encode(imageBytes)}';
  }

  void _throwIfError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = decoded['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        throw Exception(detail.trim());
      }
    } catch (_) {
      // Fall back to the raw body below.
    }

    final body = response.body.trim();
    throw Exception(
      body.isEmpty
          ? 'AI backend request failed with status ${response.statusCode}.'
          : body,
    );
  }
}

class AiBackendChatResponse {
  final String answer;
  final List<String> recommendedActions;
  final List<String> warnings;
  final List<String> sources;
  final String model;

  const AiBackendChatResponse({
    required this.answer,
    required this.recommendedActions,
    required this.warnings,
    required this.sources,
    required this.model,
  });

  factory AiBackendChatResponse.fromMap(Map<String, dynamic> map) {
    List<String> parseList(String key) {
      final raw = map[key];
      if (raw is List) {
        return raw.map((item) => item.toString()).toList();
      }
      return const [];
    }

    return AiBackendChatResponse(
      answer: (map['answer'] as String? ?? '').trim(),
      recommendedActions: parseList('recommended_actions'),
      warnings: parseList('warnings'),
      sources: parseList('sources'),
      model: (map['model'] as String? ?? 'backend').trim(),
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

