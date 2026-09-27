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
