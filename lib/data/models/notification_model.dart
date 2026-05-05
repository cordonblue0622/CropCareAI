import '../../core/constants/app_enums.dart';

class NotificationModel {
  final String id;
  final String userId;
  final String? cropId;
  final String? treatmentId;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime? scheduledFor;
  final bool isRead;
  final bool isSent;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    this.cropId,
    this.treatmentId,
    required this.type,
    required this.title,
    required this.body,
    this.scheduledFor,
    this.isRead = false,
    this.isSent = false,
    required this.createdAt,
  });

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      cropId: map['crop_id'] as String?,
      treatmentId: map['treatment_id'] as String?,
      type: NotificationTypeX.fromValue(map['type'] as String),
      title: map['title'] as String,
      body: map['body'] as String,
      scheduledFor: map['scheduled_for'] != null
          ? DateTime.tryParse(map['scheduled_for'] as String)
          : null,
      isRead: (map['is_read'] as Object?) == true ||
          (map['is_read'] as Object?) == 1,
      isSent: (map['is_sent'] as Object?) == true ||
          (map['is_sent'] as Object?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'crop_id': cropId,
      'treatment_id': treatmentId,
      'type': type.value,
      'title': title,
      'body': body,
      'scheduled_for': scheduledFor?.toIso8601String(),
      'is_read': isRead ? 1 : 0,
      'is_sent': isSent ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  NotificationModel copyWith({
    String? id,
    String? userId,
    String? cropId,
    String? treatmentId,
    NotificationType? type,
    String? title,
    String? body,
    DateTime? scheduledFor,
    bool? isRead,
    bool? isSent,
    DateTime? createdAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      cropId: cropId ?? this.cropId,
      treatmentId: treatmentId ?? this.treatmentId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      isRead: isRead ?? this.isRead,
      isSent: isSent ?? this.isSent,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
