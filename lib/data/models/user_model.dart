class UserModel {
  final String id;
  final String? fullName;
  final String? displayName;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final String? barangay;
  final String? municipality;
  final String? province;
  final String? country;
  final String preferredLanguage;
  final String provider;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserModel({
    required this.id,
    this.fullName,
    this.displayName,
    required this.email,
    this.phone,
    this.avatarUrl,
    this.barangay,
    this.municipality,
    this.province,
    this.country,
    this.preferredLanguage = 'en',
    this.provider = 'email',
    this.createdAt,
    this.updatedAt,
  });

  static String? _cleanString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get formattedLocation {
    final parts = [barangay, municipality, province]
        .map((part) => part?.trim())
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }

  String? get weatherLocationQuery {
    final parts = [barangay, municipality, province, country]
        .map((part) => part?.trim())
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as String,
      fullName: map['full_name'] as String?,
      displayName: map['display_name'] as String?,
      email: map['email'] as String,
      phone: map['phone'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      barangay: _cleanString(map['barangay']),
      municipality: _cleanString(map['municipality']),
      province: _cleanString(map['province']),
      country: _cleanString(map['country']),
      preferredLanguage: map['preferred_language'] as String? ?? 'en',
      provider: map['provider'] as String? ?? 'email',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'full_name': fullName,
      'display_name': displayName,
      'email': email,
      'phone': phone,
      'avatar_url': avatarUrl,
      'barangay': barangay,
      'municipality': municipality,
      'province': province,
      'country': country,
      'preferred_language': preferredLanguage,
      'provider': provider,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? id,
    String? fullName,
    String? displayName,
    String? email,
    String? phone,
    String? avatarUrl,
    String? barangay,
    String? municipality,
    String? province,
    String? country,
    String? preferredLanguage,
    String? provider,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      barangay: barangay ?? this.barangay,
      municipality: municipality ?? this.municipality,
      province: province ?? this.province,
      country: country ?? this.country,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      provider: provider ?? this.provider,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
