import 'package:daily_quran/domain/services/daily_goal.dart';
import 'package:flutter_test/flutter_test.dart';

/// What makes a day count towards the streak, and how the streak is counted.
void main() {
  group('DailyGoal', () {
    test('with no goal of their own, the Daily Ayah is the day’s goal', () {
      const DailyGoal goal = DailyGoal(minutes: 0, hasPlan: false);

      expect(goal.isDailyAyah, isTrue);
      expect(
        goal.isMet(secondsRead: 0, planGoalDone: false, dailyAyatRead: 1),
        isTrue,
      );
      expect(
        goal.isMet(secondsRead: 900, planGoalDone: false, dailyAyatRead: 0),
        isFalse,
      );
    });

    test('a reading time is met by reading for that long', () {
      const DailyGoal goal = DailyGoal(minutes: 10, hasPlan: false);

      expect(
        goal.isMet(secondsRead: 599, planGoalDone: false, dailyAyatRead: 3),
        isFalse,
        reason: 'reading the Daily Ayah no longer meets a bigger goal',
      );
      expect(
        goal.isMet(secondsRead: 600, planGoalDone: false, dailyAyatRead: 0),
        isTrue,
      );
    });

    test('a plan’s goal is met by finishing the day’s portion', () {
      const DailyGoal goal = DailyGoal(minutes: 0, hasPlan: true);

      expect(
        goal.isMet(secondsRead: 0, planGoalDone: false, dailyAyatRead: 1),
        isFalse,
      );
      expect(
        goal.isMet(secondsRead: 0, planGoalDone: true, dailyAyatRead: 0),
        isTrue,
      );
    });

    test('with both, meeting either one is enough', () {
      const DailyGoal goal = DailyGoal(minutes: 10, hasPlan: true);

      expect(
        goal.isMet(secondsRead: 60, planGoalDone: true, dailyAyatRead: 0),
        isTrue,
      );
      expect(
        goal.isMet(secondsRead: 600, planGoalDone: false, dailyAyatRead: 0),
        isTrue,
      );
      expect(
        goal.isMet(secondsRead: 60, planGoalDone: false, dailyAyatRead: 5),
        isFalse,
      );
    });
  });

  group('ReadingStreak', () {
    final DateTime today = DateTime(2026, 1, 10);
    DateTime daysAgo(int days) => DateTime(2026, 1, 10 - days);

    test('counts consecutive days up to today', () {
      expect(
        ReadingStreak.current(
          <DateTime>[daysAgo(0), daysAgo(1), daysAgo(2)],
          today: today,
        ),
        3,
      );
    });

    test('a day not met yet has not broken the streak', () {
      expect(
        ReadingStreak.current(
          <DateTime>[daysAgo(1), daysAgo(2)],
          today: today,
        ),
        2,
      );
    });

    test('a missed day starts it again', () {
      expect(
        ReadingStreak.current(
          <DateTime>[daysAgo(0), daysAgo(2), daysAgo(3), daysAgo(4)],
          today: today,
        ),
        1,
      );
      expect(
        ReadingStreak.current(<DateTime>[daysAgo(2)], today: today),
        0,
      );
    });

    test('is nothing with no days', () {
      expect(ReadingStreak.current(const <DateTime>[], today: today), 0);
    });

    test('counts across a daylight-saving change', () {
      // Clocks went forward in Europe on 29 March 2026.
      expect(
        ReadingStreak.current(
          <DateTime>[
            DateTime(2026, 3, 28),
            DateTime(2026, 3, 29),
            DateTime(2026, 3, 30),
          ],
          today: DateTime(2026, 3, 30),
        ),
        3,
      );
    });

    test('is celebrated every third day', () {
      expect(
        <int>[for (int day = 0; day <= 9; day++) day]
            .where(ReadingStreak.isCelebrated),
        <int>[3, 6, 9],
      );
    });
  });
}
