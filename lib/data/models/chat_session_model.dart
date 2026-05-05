class ChatSessionModel {
  final String id;
  final String userId;
  final String? cropId;
  final String? title;
  final bool isOfflineSession;
  final DateTime? lastMessageAt;
  final int syncVersion;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChatSessionModel({
    required this.id,
    required this.userId,
    this.cropId,
    this.title,
    this.isOfflineSession = false,
    this.lastMessageAt,
    this.syncVersion = 1,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatSessionModel.fromMap(Map<String, dynamic> map) {
    return ChatSessionModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      cropId: map['crop_id'] as String?,
      title: map['title'] as String?,
      isOfflineSession: (map['is_offline_session'] as Object?) == true ||
          (map['is_offline_session'] as Object?) == 1,
      lastMessageAt: map['last_message_at'] != null
          ? DateTime.tryParse(map['last_message_at'] as String)
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
      'crop_id': cropId,
      'title': title,
      'is_offline_session': isOfflineSession ? 1 : 0,
      'last_message_at': lastMessageAt?.toIso8601String(),
      'sync_version': syncVersion,
      'is_deleted': isDeleted ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  ChatSessionModel copyWith({
    String? id,
    String? userId,
    String? cropId,
    String? title,
    bool? isOfflineSession,
    DateTime? lastMessageAt,
    int? syncVersion,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatSessionModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      cropId: cropId ?? this.cropId,
      title: title ?? this.title,
      isOfflineSession: isOfflineSession ?? this.isOfflineSession,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      syncVersion: syncVersion ?? this.syncVersion,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
