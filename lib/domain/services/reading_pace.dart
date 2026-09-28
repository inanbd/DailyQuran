import '../entities/enums.dart';

/// Roughly how long reading takes, so a plan can say what a day of it will
/// ask in time as well as in ayat.
///
/// An estimate, and always presented as one. It is built from the Qur'an's
/// own averages, measured over the bundled editions — 12.4 Arabic words an
/// ayah, and 20 to 33 words of translation depending on the language — read
/// at a steady pace: the Arabic at about 65 words a minute, the pace of a
/// measured recitation that finishes the Qur'an in some twenty hours, and a
/// translation at an ordinary 200 words a minute.
///
/// Every ayah is taken at the average. The long ayat of Al-Baqarah take
/// longer and the short ones of the last juz' less, but a plan's day is
/// dozens or hundreds of them, where the average is honest enough.
abstract final class ReadingPace {
  /// Seconds the Arabic of an average ayah takes.
  static const int arabicSeconds = 12;

  /// Seconds a translation of an average ayah takes.
  static const int translationSeconds = 8;

  /// The pace of a measured recitation, which [arabicSeconds] is built on.
  static const int arabicWordsPerMinute = 65;

  /// An ordinary reading pace, which [translationSeconds] is built on.
  static const int translationWordsPerMinute = 200;

  /// The least time any ayah is taken to need, however short: long enough
  /// that a glance on the way past is not a reading.
  static const Duration shortestReading = Duration(seconds: 3);

  /// Roughly how long this one ayah takes to read, at the same pace as
  /// [secondsPerAyah] but counting its own words rather than the average's:
  /// [arabic] and each of [translations] as shown on screen, null for text
  /// that is not.
  ///
  /// What the scrolling view waits for before an ayah it has been scrolled
  /// past counts as read.
  static Duration timeFor({
    String? arabic,
    List<String?> translations = const <String?>[],
  }) {
    double seconds = _words(arabic) * 60 / arabicWordsPerMinute;
    for (final String? translation in translations) {
      seconds += _words(translation) * 60 / translationWordsPerMinute;
    }
    final Duration estimate =
        Duration(milliseconds: (seconds * 1000).round());
    return estimate < shortestReading ? shortestReading : estimate;
  }

  static int _words(String? text) {
    final String trimmed = text?.trim() ?? '';
    return trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\s+')).length;
  }

  /// Seconds an average ayah takes with [mode] on screen — and a second
  /// translation beneath the first, when [secondTranslation].
  static int secondsPerAyah(
    LanguageMode mode, {
    bool secondTranslation = false,
  }) {
    int seconds = 0;
    if (mode.showsArabic) seconds += arabicSeconds;
    if (mode.showsTranslation) {
      seconds += translationSeconds;
      if (secondTranslation) seconds += translationSeconds;
    }
    return seconds;
  }

  /// Roughly how many minutes [ayat] take at [secondsPerAyah], rounded the
  /// way a person would say it: to the minute under a quarter of an hour, to
  /// five minutes above it. Never less than a minute.
  static int minutesFor(int ayat, {required int secondsPerAyah}) {
    final double minutes = ayat * secondsPerAyah / 60;
    if (minutes < 1) return 1;
    if (minutes < 15) return minutes.round();
    return (minutes / 5).round() * 5;
  }
}
