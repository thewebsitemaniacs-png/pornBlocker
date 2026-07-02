class HabitLog {
  final String id;
  final String userId;
  final String eventType;
  final Map<String, dynamic> payload;
  final DateTime loggedAt;
  final bool synced;

  HabitLog({
    required this.id,
    required this.userId,
    required this.eventType,
    required this.payload,
    required this.loggedAt,
    this.synced = false,
  });

  HabitLog copyWith({
    String? id,
    String? userId,
    String? eventType,
    Map<String, dynamic>? payload,
    DateTime? loggedAt,
    bool? synced,
  }) {
    return HabitLog(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      eventType: eventType ?? this.eventType,
      payload: payload ?? this.payload,
      loggedAt: loggedAt ?? this.loggedAt,
      synced: synced ?? this.synced,
    );
  }

  Map<String, dynamic> toJson({bool excludeSyncFlag = false}) {
    final data = {
      'id': id,
      'user_id': userId,
      'event_type': eventType,
      'payload': payload,
      'logged_at': loggedAt.toIso8601String(),
    };
    if (!excludeSyncFlag) {
      data['synced'] = synced;
    }
    return data;
  }

  factory HabitLog.fromJson(Map<String, dynamic> json) {
    return HabitLog(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      eventType: json['event_type'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      loggedAt: DateTime.parse(json['logged_at'] as String),
      synced: json['synced'] as bool? ?? false,
    );
  }
}
