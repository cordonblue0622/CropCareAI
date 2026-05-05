import '../../core/constants/app_enums.dart';

class CropModel {
  final String id;
  final String userId;
  final CropType cropType;
  final String cropName;
  final String? plotCode;
  final String? locationLabel;
  final String? notes;
  final CropStatus status;
  final DateTime? plantedAt;
  final DateTime? lastCheckedAt;
  final ProgressStatus? latestProgressStatus;
  final double? latestHealthScore;
  final int syncVersion;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CropModel({
    required this.id,
    required this.userId,
    required this.cropType,
    required this.cropName,
    this.plotCode,
    this.locationLabel,
    this.notes,
    this.status = CropStatus.monitoring,
    this.plantedAt,
    this.lastCheckedAt,
    this.latestProgressStatus,
    this.latestHealthScore,
    this.syncVersion = 1,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CropModel.fromMap(Map<String, dynamic> map) {
    return CropModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      cropType: CropTypeX.fromValue(map['crop_type'] as String),
      cropName: map['crop_name'] as String,
      plotCode: map['plot_code'] as String?,
      locationLabel: map['location_label'] as String?,
      notes: map['notes'] as String?,
      status: CropStatusX.fromValue(map['status'] as String? ?? 'monitoring'),
      plantedAt: map['planted_at'] != null
          ? DateTime.tryParse(map['planted_at'] as String)
          : null,
      lastCheckedAt: map['last_checked_at'] != null
          ? DateTime.tryParse(map['last_checked_at'] as String)
          : null,
      latestProgressStatus: map['latest_progress_status'] != null
          ? ProgressStatusX.fromValue(map['latest_progress_status'] as String)
          : null,
      latestHealthScore: map['latest_health_score'] != null
          ? (map['latest_health_score'] as num).toDouble()
          : null,
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
      'user_id': userId,
      'crop_type': cropType.value,
      'crop_name': cropName,
      'plot_code': plotCode,
      'location_label': locationLabel,
      'notes': notes,
      'status': status.value,
      'planted_at': plantedAt?.toIso8601String(),
      'last_checked_at': lastCheckedAt?.toIso8601String(),
      'latest_progress_status': latestProgressStatus?.value,
      'latest_health_score': latestHealthScore,
      'sync_version': syncVersion,
      'is_deleted': isDeleted ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  CropModel copyWith({
    String? id,
    String? userId,
    CropType? cropType,
    String? cropName,
    String? plotCode,
    String? locationLabel,
    String? notes,
    CropStatus? status,
    DateTime? plantedAt,
    DateTime? lastCheckedAt,
    ProgressStatus? latestProgressStatus,
    double? latestHealthScore,
    int? syncVersion,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CropModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      cropType: cropType ?? this.cropType,
      cropName: cropName ?? this.cropName,
      plotCode: plotCode ?? this.plotCode,
      locationLabel: locationLabel ?? this.locationLabel,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      plantedAt: plantedAt ?? this.plantedAt,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      latestProgressStatus: latestProgressStatus ?? this.latestProgressStatus,
      latestHealthScore: latestHealthScore ?? this.latestHealthScore,
      syncVersion: syncVersion ?? this.syncVersion,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
