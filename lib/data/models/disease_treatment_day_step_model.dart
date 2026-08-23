import 'dart:convert';

class DiseaseTreatmentDayStepModel {
  final String id;
  final String diseaseKnowledgeBaseId;
  final int dayNumber;
  final String dayTitle;
  final List<String> tasks;
  final String? notes;
  final bool isActive;

  const DiseaseTreatmentDayStepModel({
    required this.id,
    required this.diseaseKnowledgeBaseId,
    required this.dayNumber,
    required this.dayTitle,
    required this.tasks,
    this.notes,
    this.isActive = true,
  });

  factory DiseaseTreatmentDayStepModel.fromMap(Map<String, dynamic> map) {
    return DiseaseTreatmentDayStepModel(
      id: map['id'] as String,
      diseaseKnowledgeBaseId: map['disease_knowledge_base_id'] as String,
      dayNumber: (map['day_number'] as num?)?.toInt() ?? 1,
      dayTitle: map['day_title'] as String? ?? 'Daily care',
      tasks: _parseTasks(map['tasks']),
      notes: map['notes'] as String?,
      isActive: (map['is_active'] as Object?) != false &&
          (map['is_active'] as Object?) != 0,
    );
  }

  static List<String> _parseTasks(dynamic raw) {
    if (raw is List) {
      return raw
          .map((task) => task.toString().trim())
          .where((task) => task.isNotEmpty)
          .toList(growable: false);
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map((task) => task.toString().trim())
              .where((task) => task.isNotEmpty)
              .toList(growable: false);
        }
      } on FormatException {
        return [raw.trim()];
      }
    }
    return const [];
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'disease_knowledge_base_id': diseaseKnowledgeBaseId,
      'day_number': dayNumber,
      'day_title': dayTitle,
      'tasks': jsonEncode(tasks),
      'notes': notes,
      'is_active': isActive ? 1 : 0,
    };
  }
}
