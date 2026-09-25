import 'package:flutter/material.dart';

/// Font families bundled with the app. Both are variable fonts shipped under
/// the SIL Open Font License (see `assets/fonts/`).
abstract final class AppFonts {
  static const String english = 'Inter';
  static const String arabic = 'NotoNaskhArabic';

  /// Fallbacks keep text readable if a glyph is missing from the bundled face.
  ///
  /// Qur'anic orthography uses marks — small high seen, imalah, the sukun and
  /// madd forms — that not every Arabic face carries. The fallbacks below are
  /// the ones most likely to be installed on a device that lacks one.
  static const List<String> arabicFallback = <String>[
    'NotoNaskhArabic',
    'Geeza Pro',
    'Noto Sans Arabic',
    'Amiri',
  ];
}

/// Reading-first type scale.
///
/// Sizes are the *base* sizes; the user's text-size preference and the
/// platform's dynamic type setting are applied on top via [TextScaler], so
/// nothing here is a hard cap.
abstract final class AppTypography {
  /// Screen titles — "Today's Ayah", "Translations".
  static const TextStyle pageTitle = TextStyle(
    fontFamily: AppFonts.english,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.2,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: AppFonts.english,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  /// Edition name / "Al-Baqarah · 2:255".
  static const TextStyle metadata = TextStyle(
    fontFamily: AppFonts.english,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.45,
  );

  /// Small caps-ish label above a group of settings.
  static const TextStyle overline = TextStyle(
    fontFamily: AppFonts.english,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: 0.6,
  );

  /// The Arabic of the Qur'an. It is the reason the screen exists, so it is
  /// set larger and more open than anything else in the app: Qur'anic
  /// orthography stacks marks above and below the line, and cramped leading
  /// collides them.
  static const TextStyle arabicBody = TextStyle(
    fontFamily: AppFonts.arabic,
    fontFamilyFallback: AppFonts.arabicFallback,
    fontSize: 28,
    fontWeight: FontWeight.w400,
    height: 2.15,
  );

  /// The translation.
  static const TextStyle translationBody = TextStyle(
    fontFamily: AppFonts.english,
    fontSize: 17.5,
    fontWeight: FontWeight.w400,
    height: 1.72,
  );

  /// Latin-script transliteration. Set apart from the translation so the two
  /// are never mistaken for each other.
  static const TextStyle transliterationBody = TextStyle(
    fontFamily: AppFonts.english,
    fontSize: 15.5,
    fontWeight: FontWeight.w400,
    height: 1.7,
    fontStyle: FontStyle.italic,
  );

  static const TextStyle body = TextStyle(
    fontFamily: AppFonts.english,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );

  /// Reference block under the ayah.
  static const TextStyle reference = TextStyle(
    fontFamily: AppFonts.english,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// The large figure on a stat — the planner's "202 a day", the ring's
  /// percentage. Tabular figures so a changing number does not sway the
  /// layout around it.
  static const TextStyle statNumeral = TextStyle(
    fontFamily: AppFonts.english,
    fontSize: 26,
    fontWeight: FontWeight.w600,
    height: 1.15,
    letterSpacing: -0.3,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  /// "24 of 6,236 read".
  static const TextStyle progressMeta = TextStyle(
    fontFamily: AppFonts.english,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  static const TextStyle button = TextStyle(
    fontFamily: AppFonts.english,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// Arabic titles shown in lists, e.g. البقرة.
  static const TextStyle arabicTitle = TextStyle(
    fontFamily: AppFonts.arabic,
    fontFamilyFallback: AppFonts.arabicFallback,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.7,
  );
}
