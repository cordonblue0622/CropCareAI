import 'dart:convert';
import '../../core/constants/app_enums.dart';

class DiseaseKnowledgeModel {
  final String id;
  final CropType cropType;
  final String? labelKey;
  final String diseaseName;
  final String? scientificName;
  final String? description;
  final List<String>? symptoms;
  final List<String>? causes;
  final List<String>? treatmentSteps;
  final List<String>? preventionSteps;
  final int? estimatedRecoveryDays;
  final String? severityNotes;
  final String? cautionNotes;
  final bool isActive;
  final String? sourceName;
  final String? sourceUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DiseaseKnowledgeModel({
    required this.id,
    required this.cropType,
    this.labelKey,
    required this.diseaseName,
    this.scientificName,
    this.description,
    this.symptoms,
    this.causes,
    this.treatmentSteps,
    this.preventionSteps,
    this.estimatedRecoveryDays,
    this.severityNotes,
    this.cautionNotes,
    this.isActive = true,
    this.sourceName,
    this.sourceUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DiseaseKnowledgeModel.fromMap(Map<String, dynamic> map) {
    List<String>? parseStringList(dynamic raw) {
      if (raw == null) return null;
      if (raw is List) return List<String>.from(raw);
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is List) return List<String>.from(decoded);
      }
      return null;
    }

    return DiseaseKnowledgeModel(
      id: map['id'] as String,
      cropType: CropTypeX.fromValue(map['crop_type'] as String),
      labelKey: map['label_key'] as String?,
      diseaseName: map['disease_name'] as String,
      scientificName: map['scientific_name'] as String?,
      description: map['description'] as String?,
      symptoms: parseStringList(map['symptoms']),
      causes: parseStringList(map['causes']),
      treatmentSteps: parseStringList(map['treatment_steps']),
      preventionSteps: parseStringList(map['prevention_steps']),
      estimatedRecoveryDays: map['estimated_recovery_days'] as int?,
      severityNotes: map['severity_notes'] as String?,
      cautionNotes: map['caution_notes'] as String?,
      isActive: (map['is_active'] as Object?) != false &&
          (map['is_active'] as Object?) != 0,
      sourceName: map['source_name'] as String?,
      sourceUrl: map['source_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'crop_type': cropType.value,
      'label_key': labelKey,
      'disease_name': diseaseName,
      'scientific_name': scientificName,
      'description': description,
      'symptoms': symptoms != null ? jsonEncode(symptoms) : null,
      'causes': causes != null ? jsonEncode(causes) : null,
      'treatment_steps':
          treatmentSteps != null ? jsonEncode(treatmentSteps) : null,
      'prevention_steps':
          preventionSteps != null ? jsonEncode(preventionSteps) : null,
      'estimated_recovery_days': estimatedRecoveryDays,
      'severity_notes': severityNotes,
      'caution_notes': cautionNotes,
      'is_active': isActive ? 1 : 0,
      'source_name': sourceName,
      'source_url': sourceUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
