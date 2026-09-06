import 'package:meta/meta.dart';

import 'enums.dart';

/// One of the Qur'an's surahs (chapters).
///
/// This is bibliographic reference data — names, lengths, classification — and
/// never contains Qur'an text. It ships with the app so the surah index works
/// before any edition has been imported.
@immutable
class Surah {
  const Surah({
    required this.editionId,
    required this.number,
    required this.nameArabic,
    required this.nameTransliterated,
    required this.nameEnglish,
    required this.ayahCount,
    this.revelationPlace = RevelationPlace.unknown,
  });

  final String editionId;

  /// 1–114 in a complete edition.
  final int number;

  /// Native name, e.g. `البقرة`.
  final String nameArabic;

  /// Latin-script name, e.g. `Al-Baqarah`.
  final String nameTransliterated;

  /// Translated name, e.g. `The Cow`. Empty when the source has none.
  final String nameEnglish;

  final int ayahCount;

  /// Meccan or Medinan, as classified by the source.
  final RevelationPlace revelationPlace;

  /// The one-line name used in lists: `Al-Baqarah · The Cow`.
  String get displayName {
    if (nameTransliterated.isEmpty) return nameEnglish;
    if (nameEnglish.isEmpty) return nameTransliterated;
    return '$nameTransliterated · $nameEnglish';
  }

  @override
  bool operator ==(Object other) =>
      other is Surah && other.editionId == editionId && other.number == number;

  @override
  int get hashCode => Object.hash(editionId, number);
}
