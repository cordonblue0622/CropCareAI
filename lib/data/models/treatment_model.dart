import 'dart:convert';
import '../../core/constants/app_enums.dart';

class TreatmentModel {
  final String id;
  final String cropId;
  final String? diagnosisId;
  final String userId;
  final String diseaseName;
  final String treatmentTitle;
  final List<String> treatmentSteps;
  final int? expectedDurationDays;
  final TreatmentStatus status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final bool reassessmentRequired;
  final String? notes;
  final String source;
  final int syncVersion;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TreatmentModel({
    required this.id,
    required this.cropId,
    this.diagnosisId,
    required this.userId,
    required this.diseaseName,
    required this.treatmentTitle,
    required this.treatmentSteps,
    this.expectedDurationDays,
    this.status = TreatmentStatus.planned,
    this.startedAt,
    this.endedAt,
    this.reassessmentRequired = false,
    this.notes,
    this.source = 'knowledge_base',
    this.syncVersion = 1,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TreatmentModel.fromMap(Map<String, dynamic> map) {
    List<String> parseStringList(dynamic raw) {
      if (raw == null) return [];
      if (raw is List) return List<String>.from(raw);
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is List) return List<String>.from(decoded);
      }
      return [];
    }

    return TreatmentModel(
      id: map['id'] as String,
      cropId: map['crop_id'] as String,
      diagnosisId: map['diagnosis_id'] as String?,
      userId: map['user_id'] as String,
      diseaseName: map['disease_name'] as String,
      treatmentTitle: map['treatment_title'] as String,
      treatmentSteps: parseStringList(map['treatment_steps']),
      expectedDurationDays: map['expected_duration_days'] as int?,
      status: TreatmentStatusX.fromValue(map['status'] as String? ?? 'planned'),
      startedAt: map['started_at'] != null
          ? DateTime.tryParse(map['started_at'] as String)
          : null,
      endedAt: map['ended_at'] != null
          ? DateTime.tryParse(map['ended_at'] as String)
          : null,
      reassessmentRequired:
          (map['reassessment_required'] as Object?) == true ||
              (map['reassessment_required'] as Object?) == 1,
      notes: map['notes'] as String?,
      source: map['source'] as String? ?? 'knowledge_base',
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
      'diagnosis_id': diagnosisId,
      'user_id': userId,
      'disease_name': diseaseName,
      'treatment_title': treatmentTitle,
      'treatment_steps': jsonEncode(treatmentSteps),
      'expected_duration_days': expectedDurationDays,
      'status': status.value,
      'started_at': startedAt?.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'reassessment_required': reassessmentRequired,
      'notes': notes,
      'source': source,
      'sync_version': syncVersion,
      'is_deleted': isDeleted,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
