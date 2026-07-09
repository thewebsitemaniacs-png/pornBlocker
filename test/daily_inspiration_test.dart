import 'package:flutter_test/flutter_test.dart';
import 'package:habit_breaker/features/habit_engine/domain/entities/daily_inspiration.dart';

void main() {
  group('DailyInspiration Model Tests', () {
    test('fromJson initializes correctly from newline separated string', () {
      final json = {
        'id': 42,
        'verse': 'Jesus wept.',
        'reference': 'John 11:35',
        'confessions': 'I walk in love and peace.\nI am courageous.\n\n',
      };

      final inspiration = DailyInspiration.fromJson(json);

      expect(inspiration.id, 42);
      expect(inspiration.verse, 'Jesus wept.');
      expect(inspiration.reference, 'John 11:35');
      expect(inspiration.confessions.length, 2);
      expect(inspiration.confessions[0], 'I walk in love and peace.');
      expect(inspiration.confessions[1], 'I am courageous.');
    });

    test('toJson returns correct map representation with newline separation', () {
      final inspiration = DailyInspiration(
        id: 99,
        verse: 'Rejoice always.',
        reference: '1 Thessalonians 5:16',
        confessions: ['I choose joy.', 'I walk in faith.'],
      );

      final json = inspiration.toJson();

      expect(json['id'], 99);
      expect(json['verse'], 'Rejoice always.');
      expect(json['reference'], '1 Thessalonians 5:16');
      expect(json['confessions'], 'I choose joy.\nI walk in faith.');
    });
  });
}
