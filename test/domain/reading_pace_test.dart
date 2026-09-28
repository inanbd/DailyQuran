import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/services/reading_pace.dart';
import 'package:flutter_test/flutter_test.dart';

/// Roughly how long a day of reading takes, for the planner to say so.
void main() {
  test('an ayah takes longer the more of it is on screen', () {
    expect(ReadingPace.secondsPerAyah(LanguageMode.translation), 8);
    expect(ReadingPace.secondsPerAyah(LanguageMode.arabic), 12);
    expect(ReadingPace.secondsPerAyah(LanguageMode.both), 20);
    expect(
      ReadingPace.secondsPerAyah(LanguageMode.both, secondTranslation: true),
      28,
    );
  });

  test('a second translation adds nothing when only the Arabic is shown', () {
    expect(
      ReadingPace.secondsPerAyah(LanguageMode.arabic, secondTranslation: true),
      12,
    );
  });

  test('a month’s plan is a little over an hour a day', () {
    // 6,236 ayat over 31 days is 202 a day.
    expect(ReadingPace.minutesFor(202, secondsPerAyah: 20), 65);
  });

  test('a year’s plan is a few minutes a day', () {
    expect(ReadingPace.minutesFor(18, secondsPerAyah: 20), 6);
  });

  group('one ayah, by its own words', () {
    test('takes its Arabic at a recitation’s pace and a translation at a '
        'reader’s', () {
      // 13 Arabic words at 65 a minute is 12 s; 40 of translation at 200, 12 s.
      final String arabic = List<String>.filled(13, 'كلمة').join(' ');
      final String translation = List<String>.filled(40, 'word').join(' ');

      expect(ReadingPace.timeFor(arabic: arabic), const Duration(seconds: 12));
      expect(
        ReadingPace.timeFor(arabic: arabic, translations: <String?>[translation]),
        const Duration(seconds: 24),
      );
      expect(
        ReadingPace.timeFor(
          arabic: arabic,
          translations: <String?>[translation, translation],
        ),
        const Duration(seconds: 36),
      );
    });

    test('is never less than a glance takes, however short', () {
      expect(ReadingPace.timeFor(arabic: 'الم'), ReadingPace.shortestReading);
      expect(ReadingPace.timeFor(), ReadingPace.shortestReading);
    });

    test('counts only what is on screen', () {
      final String translation = List<String>.filled(100, 'word').join(' ');
      expect(
        ReadingPace.timeFor(translations: <String?>[translation, null]),
        const Duration(seconds: 30),
      );
    });
  });

  test('is rounded the way a person would say it', () {
    // To the minute under a quarter of an hour…
    expect(ReadingPace.minutesFor(40, secondsPerAyah: 20), 13);
    // …to five minutes above it…
    expect(ReadingPace.minutesFor(50, secondsPerAyah: 20), 15);
    expect(ReadingPace.minutesFor(100, secondsPerAyah: 20), 35);
    // …and never less than a minute.
    expect(ReadingPace.minutesFor(1, secondsPerAyah: 8), 1);
  });
}
