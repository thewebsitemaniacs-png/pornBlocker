class UserProfile {
  final String id;
  final String username;
  final bool isPremium;
  final bool isSupporter;
  final String? buddyId;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfile({
    required this.id,
    required this.username,
    required this.isPremium,
    this.isSupporter = false,
    this.buddyId,
    required this.createdAt,
    required this.updatedAt,
  });

  UserProfile copyWith({
    String? id,
    String? username,
    bool? isPremium,
    bool? isSupporter,
    String? buddyId,
    bool clearBuddy = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      isPremium: isPremium ?? this.isPremium,
      isSupporter: isSupporter ?? this.isSupporter,
      buddyId: clearBuddy ? null : (buddyId ?? this.buddyId),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'is_premium': isPremium,
      'is_supporter': isSupporter,
      'buddy_id': buddyId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      isPremium: json['is_premium'] as bool? ?? false,
      isSupporter: json['is_supporter'] as bool? ?? false,
      buddyId: json['buddy_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
