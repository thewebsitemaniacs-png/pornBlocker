class DailyInspiration {
  final int id;
  final String verse;
  final String reference;
  final List<String> confessions;

  DailyInspiration({
    required this.id,
    required this.verse,
    required this.reference,
    required this.confessions,
  });

  factory DailyInspiration.fromJson(Map<String, dynamic> json) {
    final rawConfessions = json['confessions'].toString();
    final list = rawConfessions
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return DailyInspiration(
      id: json['id'] as int,
      verse: json['verse'] as String,
      reference: json['reference'] as String,
      confessions: list,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'verse': verse,
      'reference': reference,
      'confessions': confessions.join('\n'),
    };
  }
}
