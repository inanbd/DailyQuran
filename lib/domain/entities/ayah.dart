import 'package:meta/meta.dart';

/// A single ayah as stored and displayed.
///
/// Text fields are reproduced verbatim from the configured content source and
/// are never generated, paraphrased, completed or edited by the app.
@immutable
class Ayah {
  const Ayah({
    required this.id,
    required this.editionId,
    required this.ordinal,
    required this.surahNumber,
    required this.ayahNumber,
    this.surahNameArabic,
    this.surahNameEnglish,
    this.arabicText,
    this.translationText,
    this.transliteration,
    this.juz,
    this.page,
    this.sajda = false,
    this.reference,
    this.source,
  });

  /// Globally unique id within an edition, e.g. `saheeh_international:2:255`.
  final String id;

  final String editionId;

  /// 1-based reading position within the edition. This is the sequence the app
  /// reads in — mushaf order for a complete edition.
  final int ordinal;

  /// Surah this ayah belongs to (1–114 in a complete edition).
  final int surahNumber;

  /// Number of the ayah within its surah, as published by the source.
  final int ayahNumber;

  final String? surahNameArabic;
  final String? surahNameEnglish;

  /// The Arabic of the Qur'an. Null when the source has no Arabic for this
  /// entry — a gap in the dataset stays a gap.
  final String? arabicText;

  /// The translation. Null when the source has no translation for this entry.
  final String? translationText;

  /// Latin-script transliteration of the Arabic, when the source carries one.
  final String? transliteration;

  /// Juz' (part) this ayah falls in, 1–30, when the source says.
  final int? juz;

  /// Mushaf page number, when the source says.
  final int? page;

  /// Whether the source marks this as an ayah of prostration. Never inferred.
  final bool sajda;

  /// Citation string, e.g. "Al-Baqarah 2:255".
  final String? reference;

  /// Per-ayah attribution, when it differs from the edition's.
  final String? source;

  /// The edition-independent identity of this ayah, e.g. `2:255`.
  ///
  /// Reading progress and favourites are keyed by this rather than by [id]:
  /// ayah 2:255 is the same ayah whichever translation renders it, so a reader
  /// who switches translation keeps their place and their saved ayat.
  String get verseKey => '$surahNumber:$ayahNumber';

  bool get hasArabic => (arabicText ?? '').trim().isNotEmpty;
  bool get hasTranslation => (translationText ?? '').trim().isNotEmpty;
  bool get hasTransliteration => (transliteration ?? '').trim().isNotEmpty;
  bool get hasAnyText => hasArabic || hasTranslation;

  @override
  bool operator ==(Object other) => other is Ayah && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
