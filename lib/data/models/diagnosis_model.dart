import 'dart:convert';
import '../../core/constants/app_enums.dart';

class DiagnosisModel {
  final String id;
  final String cropId;
  final String userId;
  final String? chatSessionId;
  final DiagnosisMode diagnosisMode;
  final String? labelKey;
  final String diseaseName;
  final double? confidenceScore;
  final Severity severity;
  final String? resultLabel;
  final String? summary;
  final String? imageUrl;
  final String? videoUrl;
  final Map<String, dynamic>? detectedRegionsJson;
  final String? modelName;
  final String? modelVersion;
  final DateTime diagnosedAt;
  final int syncVersion;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DiagnosisModel({
    required this.id,
    required this.cropId,
    required this.userId,
    this.chatSessionId,
    required this.diagnosisMode,
    this.labelKey,
    required this.diseaseName,
    this.confidenceScore,
    this.severity = Severity.mild,
    this.resultLabel,
    this.summary,
    this.imageUrl,
    this.videoUrl,
    this.detectedRegionsJson,
    this.modelName,
    this.modelVersion,
    required this.diagnosedAt,
    this.syncVersion = 1,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DiagnosisModel.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? regions;
    final rawRegions = map['detected_regions_json'];
    if (rawRegions is String) {
      regions = jsonDecode(rawRegions) as Map<String, dynamic>?;
    } else if (rawRegions is Map) {
      regions = Map<String, dynamic>.from(rawRegions);
    }

    return DiagnosisModel(
      id: map['id'] as String,
      cropId: map['crop_id'] as String,
      userId: map['user_id'] as String,
      chatSessionId: map['chat_session_id'] as String?,
      diagnosisMode: DiagnosisModeX.fromValue(
          map['diagnosis_mode'] as String? ?? 'offline'),
      labelKey: map['label_key'] as String?,
      diseaseName: map['disease_name'] as String,
      confidenceScore: map['confidence_score'] != null
          ? (map['confidence_score'] as num).toDouble()
          : null,
      severity: SeverityX.fromValue(map['severity'] as String? ?? 'mild'),
      resultLabel: map['result_label'] as String?,
      summary: map['summary'] as String?,
      imageUrl: map['image_url'] as String?,
      videoUrl: map['video_url'] as String?,
      detectedRegionsJson: regions,
      modelName: map['model_name'] as String?,
      modelVersion: map['model_version'] as String?,
      diagnosedAt: DateTime.parse(map['diagnosed_at'] as String),
      syncVersion: map['sync_version'] as int? ?? 1,
      isDeleted: (map['is_deleted'] as Object?) == true ||
          (map['is_deleted'] as Object?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'crop_id': cropId,
      'user_id': userId,
      'chat_session_id': chatSessionId,
      'diagnosis_mode': diagnosisMode.value,
      'label_key': labelKey,
      'disease_name': diseaseName,
      'confidence_score': confidenceScore,
      'severity': severity.value,
      'result_label': resultLabel,
      'summary': summary,
      'image_url': imageUrl,
      'video_url': videoUrl,
      'detected_regions_json':
          detectedRegionsJson != null ? jsonEncode(detectedRegionsJson) : null,
      'model_name': modelName,
      'model_version': modelVersion,
      'diagnosed_at': diagnosedAt.toIso8601String(),
      'sync_version': syncVersion,
      'is_deleted': isDeleted,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
