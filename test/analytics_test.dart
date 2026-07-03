import 'package:flutter_test/flutter_test.dart';

String toDateString(DateTime dt) {
  return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
}

int calculateCurrentStreak(Set<String> violationDays, DateTime joinedDate) {
  int streak = 0;
  DateTime checkDate = DateTime.now();
  final joinedStr = toDateString(joinedDate);
  while (true) {
    final dateStr = toDateString(checkDate);
    if (violationDays.contains(dateStr)) {
      break;
    }
    streak++;
    if (dateStr == joinedStr) {
      break;
    }
    checkDate = checkDate.subtract(const Duration(days: 1));
    if (streak > 365) break;
  }
  return streak;
}

int calculateLongestStreak(Set<String> violationDays, DateTime joinedDate) {
  int longest = 0;
  int current = 0;
  DateTime checkDate = joinedDate;
  final todayStr = toDateString(DateTime.now());
  
  while (true) {
    final dateStr = toDateString(checkDate);
    if (violationDays.contains(dateStr)) {
      current = 0;
    } else {
      current++;
      if (current > longest) {
        longest = current;
      }
    }
    if (dateStr == todayStr) {
      break;
    }
    checkDate = checkDate.add(const Duration(days: 1));
    if (checkDate.isAfter(DateTime.now().add(const Duration(days: 2)))) {
      break;
    }
  }
  return longest;
}

void main() {
  group('Analytics Streak Calculations Tests', () {
    test('calculateCurrentStreak returns 0 if today has violation', () {
      final todayStr = toDateString(DateTime.now());
      final violationDays = {todayStr};
      final joinedDate = DateTime.now().subtract(const Duration(days: 10));

      final streak = calculateCurrentStreak(violationDays, joinedDate);
      expect(streak, 0);
    });

    test('calculateCurrentStreak returns 2 if yesterday and today are clean, but day before had violation', () {
      final today = DateTime.now();
      final twoDaysAgoStr = toDateString(today.subtract(const Duration(days: 2)));
      final violationDays = {twoDaysAgoStr};
      final joinedDate = today.subtract(const Duration(days: 10));

      final streak = calculateCurrentStreak(violationDays, joinedDate);
      expect(streak, 2);
    });

    test('calculateLongestStreak counts longest consecutive sequence correctly', () {
      final today = DateTime.now();
      final joinedDate = today.subtract(const Duration(days: 6));
      
      final violationDays = {
        toDateString(today.subtract(const Duration(days: 2))),
        toDateString(today.subtract(const Duration(days: 5))),
      };

      final longest = calculateLongestStreak(violationDays, joinedDate);
      expect(longest, 2);
    });
  });
}
