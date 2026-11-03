import 'dart:convert';
import '../../core/constants/app_enums.dart';

class ProgressUpdateModel {
  final String id;
  final String cropId;
  final String? treatmentId;
  final String? diagnosisId;
  final String userId;
  final UpdateSource updateSource;
  final String? note;
  final String? imageUrl;
  final String? videoUrl;
  final List<String>? observedSymptoms;
  final String? detectedDiseaseName;
  final Severity? detectedSeverity;
  final ProgressStatus progressStatus;
  final double? healthScore;
  final int completedTaskCount;
  final int missedTaskCount;
  final DateTime updateDate;
  final AiAnalysisStatus aiAnalysisStatus;
  final String? aiAnalysisError;
  final DateTime? aiAnalysisStartedAt;
  final int syncVersion;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProgressUpdateModel({
    required this.id,
    required this.cropId,
    this.treatmentId,
    this.diagnosisId,
    required this.userId,
    this.updateSource = UpdateSource.manual,
    this.note,
    this.imageUrl,
    this.videoUrl,
    this.observedSymptoms,
    this.detectedDiseaseName,
    this.detectedSeverity,
    this.progressStatus = ProgressStatus.insufficientData,
    this.healthScore,
    this.completedTaskCount = 0,
    this.missedTaskCount = 0,
    required this.updateDate,
    this.aiAnalysisStatus = AiAnalysisStatus.notRequired,
    this.aiAnalysisError,
    this.aiAnalysisStartedAt,
    this.syncVersion = 1,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProgressUpdateModel.fromMap(Map<String, dynamic> map) {
    List<String>? parseStringList(dynamic raw) {
      if (raw == null) return null;
      if (raw is List) return List<String>.from(raw);
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is List) return List<String>.from(decoded);
      }
      return null;
    }

    final rawAnalysisStatus = map['ai_analysis_status'] as String?;
    final inferredAnalysisStatus = map['image_url'] is String &&
            (map['image_url'] as String).trim().isNotEmpty &&
            map['progress_status'] == ProgressStatus.insufficientData.value
        ? AiAnalysisStatus.pending
        : AiAnalysisStatus.notRequired;

    return ProgressUpdateModel(
      id: map['id'] as String,
      cropId: map['crop_id'] as String,
      treatmentId: map['treatment_id'] as String?,
      diagnosisId: map['diagnosis_id'] as String?,
      userId: map['user_id'] as String,
      updateSource:
          UpdateSourceX.fromValue(map['update_source'] as String? ?? 'manual'),
      note: map['note'] as String?,
      imageUrl: map['image_url'] as String?,
      videoUrl: map['video_url'] as String?,
      observedSymptoms: parseStringList(map['observed_symptoms']),
      detectedDiseaseName: map['detected_disease_name'] as String?,
      detectedSeverity: map['detected_severity'] != null
          ? SeverityX.fromValue(map['detected_severity'] as String)
          : null,
      progressStatus: ProgressStatusX.fromValue(
          map['progress_status'] as String? ?? 'insufficient_data'),
      healthScore: map['health_score'] != null
          ? (map['health_score'] as num).toDouble()
          : null,
      completedTaskCount: map['completed_task_count'] as int? ?? 0,
      missedTaskCount: map['missed_task_count'] as int? ?? 0,
      updateDate: DateTime.parse(map['update_date'] as String),
      aiAnalysisStatus: rawAnalysisStatus == null
          ? inferredAnalysisStatus
          : AiAnalysisStatusX.fromValue(rawAnalysisStatus),
      aiAnalysisError: map['ai_analysis_error'] as String?,
      aiAnalysisStartedAt: map['ai_analysis_started_at'] == null
          ? null
          : DateTime.tryParse(map['ai_analysis_started_at'] as String),
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
      'treatment_id': treatmentId,
      'diagnosis_id': diagnosisId,
      'user_id': userId,
      'update_source': updateSource.value,
      'note': note,
      'image_url': imageUrl,
      'video_url': videoUrl,
      'observed_symptoms':
          observedSymptoms != null ? jsonEncode(observedSymptoms) : null,
      'detected_disease_name': detectedDiseaseName,
      'detected_severity': detectedSeverity?.value,
      'progress_status': progressStatus.value,
      'health_score': healthScore,
      'completed_task_count': completedTaskCount,
      'missed_task_count': missedTaskCount,
      'update_date': updateDate.toIso8601String(),
      'ai_analysis_status': aiAnalysisStatus.value,
      'ai_analysis_error': aiAnalysisError,
      'ai_analysis_started_at': aiAnalysisStartedAt?.toIso8601String(),
      'sync_version': syncVersion,
      'is_deleted': isDeleted,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Fields in this map match the existing Supabase table. AI processing
  /// bookkeeping stays in SQLite and is not sent to Supabase.
  Map<String, dynamic> toRemoteMap() {
    final map = toMap()
      ..remove('ai_analysis_status')
      ..remove('ai_analysis_error')
      ..remove('ai_analysis_started_at');
    return map;
  }
}
