import 'dart:convert';
import 'dart:typed_data';
import '../../core/constants/app_enums.dart';

class ChatMessageModel {
  final String id;
  final String sessionId;
  final String userId;
  final MessageRole role;
  final String content;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  /// In-memory only — not persisted to the database.
  final Uint8List? imageBytes;
  /// In-memory only — marks this message's image as a video frame capture.
  final bool isVideoFrame;

  /// URL of the image stored in Supabase Storage. Persisted via metadata.
  String? get imageUrl => metadata?['image_url'] as String?;

  const ChatMessageModel({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.role,
    required this.content,
    this.metadata,
    required this.createdAt,
    this.imageBytes,
    this.isVideoFrame = false,
  });

  ChatMessageModel copyWith({
    String? id,
    String? sessionId,
    String? userId,
    MessageRole? role,
    String? content,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    Uint8List? imageBytes,
    bool? isVideoFrame,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      content: content ?? this.content,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      imageBytes: imageBytes ?? this.imageBytes,
      isVideoFrame: isVideoFrame ?? this.isVideoFrame,
    );
  }

  factory ChatMessageModel.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? meta;
    final rawMeta = map['metadata'];
    if (rawMeta is String) {
      meta = jsonDecode(rawMeta) as Map<String, dynamic>?;
    } else if (rawMeta is Map) {
      meta = Map<String, dynamic>.from(rawMeta);
    }

    return ChatMessageModel(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      userId: map['user_id'] as String,
      role: MessageRoleX.fromValue(map['role'] as String),
      content: map['content'] as String,
      metadata: meta,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'user_id': userId,
      'role': role.value,
      'content': content,
      'metadata': metadata != null ? jsonEncode(metadata) : null,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
