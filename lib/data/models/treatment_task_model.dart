import '../../core/constants/app_enums.dart';

class TreatmentTaskModel {
  final String id;
  final String treatmentId;
  final String cropId;
  final String userId;
  final String title;
  final String? description;
  final DateTime dueAt;
  final DateTime? completedAt;
  final TaskStatus status;
  final int? taskOrder;
  final int syncVersion;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  DateTime get overdueAt {
    final localDueAt = dueAt.toLocal();
    return DateTime(localDueAt.year, localDueAt.month, localDueAt.day, 19);
  }

  bool isOverdueAt(DateTime now) =>
      !isDeleted &&
      status == TaskStatus.pending &&
      !now.toLocal().isBefore(overdueAt);

  const TreatmentTaskModel({
    required this.id,
    required this.treatmentId,
    required this.cropId,
    required this.userId,
    required this.title,
    this.description,
    required this.dueAt,
    this.completedAt,
    this.status = TaskStatus.pending,
    this.taskOrder,
    this.syncVersion = 1,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TreatmentTaskModel.fromMap(Map<String, dynamic> map) {
    return TreatmentTaskModel(
      id: map['id'] as String,
      treatmentId: map['treatment_id'] as String,
      cropId: map['crop_id'] as String,
      userId: map['user_id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      dueAt: DateTime.parse(map['due_at'] as String),
      completedAt: map['completed_at'] != null
          ? DateTime.tryParse(map['completed_at'] as String)
          : null,
      status: TaskStatusX.fromValue(map['status'] as String? ?? 'pending'),
      taskOrder: map['task_order'] as int?,
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
      'treatment_id': treatmentId,
      'crop_id': cropId,
      'user_id': userId,
      'title': title,
      'description': description,
      'due_at': dueAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'status': status.value,
      'task_order': taskOrder,
      'sync_version': syncVersion,
      'is_deleted': isDeleted ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  TreatmentTaskModel copyWith({
    String? id,
    String? treatmentId,
    String? cropId,
    String? userId,
    String? title,
    String? description,
    DateTime? dueAt,
    DateTime? completedAt,
    TaskStatus? status,
    int? taskOrder,
    int? syncVersion,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TreatmentTaskModel(
      id: id ?? this.id,
      treatmentId: treatmentId ?? this.treatmentId,
      cropId: cropId ?? this.cropId,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      dueAt: dueAt ?? this.dueAt,
      completedAt: completedAt ?? this.completedAt,
      status: status ?? this.status,
      taskOrder: taskOrder ?? this.taskOrder,
      syncVersion: syncVersion ?? this.syncVersion,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
