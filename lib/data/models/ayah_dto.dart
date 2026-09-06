import '../../domain/entities/ayah.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/surah.dart';

/// Parses ayah entries from an edition file.
///
/// Text is copied through untouched — no trimming of content, no
/// normalisation, no substitution. Only whitespace-only values become null.
abstract final class AyahDto {
  static Ayah fromJson(
    Map<String, Object?> json, {
    required String editionId,
    required int ordinal,
    String? fallbackSource,
  }) {
    final int surahNumber = _int(json['surah']) ?? _int(json['surahNumber']) ?? 0;
    final int ayahNumber =
        _int(json['ayah']) ?? _int(json['ayahNumber']) ?? ordinal;
    return Ayah(
      id: '$editionId:$surahNumber:$ayahNumber',
      editionId: editionId,
      ordinal: ordinal,
      surahNumber: surahNumber,
      ayahNumber: ayahNumber,
      surahNameArabic: _string(json['surahNameArabic']),
      surahNameEnglish: _string(json['surahNameEnglish']),
      arabicText: _string(json['arabic']),
      translationText: _string(json['translation']),
      transliteration: _string(json['transliteration']),
      juz: _int(json['juz']),
      page: _int(json['page']),
      sajda: _bool(json['sajda']),
      reference: _string(json['reference']),
      source: _string(json['source']) ?? fallbackSource,
    );
  }

  static Surah surahFromJson(
    Map<String, Object?> json, {
    required String editionId,
  }) {
    return Surah(
      editionId: editionId,
      number: _int(json['number']) ?? _int(json['surahNumber']) ?? 0,
      nameArabic: _string(json['nameArabic']) ?? '',
      nameTransliterated: _string(json['nameTransliterated']) ?? '',
      nameEnglish: _string(json['nameEnglish']) ?? '',
      ayahCount: _int(json['ayahCount']) ?? 0,
      revelationPlace:
          RevelationPlace.fromStorage(json['revelationPlace'] as String?),
    );
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    return value.trim().isEmpty ? null : value;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// A sajda marking is only true when the source says so. Anything else —
  /// absent, null, an unrecognised value — is false: the app never infers one.
  static bool _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final String normalised = value.trim().toLowerCase();
      return normalised == 'true' || normalised == 'yes' || normalised == '1';
    }
    return false;
  }
}
