import 'package:daily_quran/domain/services/encouragement.dart';
import 'package:flutter_test/flutter_test.dart';

/// When a word of congratulation is due, and that it is only ever praise.
void main() {
  group('milestones', () {
    test('every tenth of the Qur’an is marked as it is crossed', () {
      // 624 of 6,236 is the first ayah past a tenth.
      expect(
        Encouragement.crossedMilestone(before: 623, after: 624, total: 6236),
        10,
      );
      expect(
        Encouragement.crossedMilestone(before: 3117, after: 3118, total: 6236),
        50,
      );
    });

    test('nothing is marked between tenths', () {
      expect(
        Encouragement.crossedMilestone(before: 624, after: 625, total: 6236),
        isNull,
      );
    });

    test('finishing is left to the completion screen', () {
      expect(
        Encouragement.crossedMilestone(before: 9, after: 10, total: 10),
        isNull,
      );
    });

    test('reading nothing new crosses nothing', () {
      expect(
        Encouragement.crossedMilestone(before: 624, after: 624, total: 6236),
        isNull,
      );
      expect(
        Encouragement.crossedMilestone(before: 625, after: 623, total: 6236),
        isNull,
      );
    });

    test('names the reading it was reached on', () {
      expect(
        Encouragement.milestone(30, isPlan: true).message,
        contains('Your plan'),
      );
      expect(
        Encouragement.milestone(30, isPlan: false).message,
        contains('Daily Ayah'),
      );
      expect(Encouragement.milestone(30, isPlan: false).title, '30% of the Qur’an');
    });
  });

  group('reading time', () {
    test('is congratulated the moment it is reached, and only then', () {
      expect(
        Encouragement.reachedReadingTime(before: 590, after: 610, minutes: 10),
        isTrue,
      );
      expect(
        Encouragement.reachedReadingTime(before: 610, after: 630, minutes: 10),
        isFalse,
      );
      expect(
        Encouragement.reachedReadingTime(before: 0, after: 610, minutes: 0),
        isFalse,
        reason: 'no goal, nothing to reach',
      );
    });

    test('reading longer than yesterday is noticed once, as it happens', () {
      expect(
        Encouragement.readLonger(before: 290, after: 310, yesterday: 300),
        isTrue,
      );
      expect(
        Encouragement.readLonger(before: 310, after: 330, yesterday: 300),
        isFalse,
      );
    });

    test('a few seconds yesterday is no reading to beat', () {
      expect(
        Encouragement.readLonger(before: 0, after: 90, yesterday: 20),
        isFalse,
      );
    });

    test('is put in words a reader would use', () {
      expect(Encouragement.readingTimeWords(30), 'under a minute');
      expect(Encouragement.readingTimeWords(12 * 60 + 40), '12 min');
      expect(Encouragement.readingTimeWords(60 * 60), '1 h');
      expect(Encouragement.readingTimeWords(65 * 60), '1 h 5 min');
    });
  });

  group('the week', () {
    test('praises a week read longer than the one before', () {
      expect(
        Encouragement.weekTrend(week: 50 * 60, previous: 35 * 60),
        'Up 15 min on the week before. MashaAllah — keep it up.',
      );
    });

    test('never scolds a shorter week', () {
      final String line =
          Encouragement.weekTrend(week: 20 * 60, previous: 35 * 60);

      expect(line, 'The week before: 35 min.');
    });

    test('welcomes a first week', () {
      expect(
        Encouragement.weekTrend(week: 5 * 60, previous: 0),
        'A good start this week — keep it going.',
      );
    });
  });

  test('a streak is told in days', () {
    expect(Encouragement.streak(3).title, '3 days in a row');
    expect(Encouragement.streak(6).message, contains('6 days running'));
  });
}
