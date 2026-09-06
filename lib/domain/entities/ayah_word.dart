import 'package:meta/meta.dart';

/// One word of an ayah, with the gloss the source gives for it.
///
/// A word-by-word gloss is a reading aid for the Arabic — it says what this
/// word means on its own, not what the ayah means. The app renders the two
/// differently and never substitutes one for the other.
///
/// Like every other text in this app, both fields are copied verbatim from the
/// source. Nothing here is glossed, completed or corrected by the app.
@immutable
class AyahWord {
  const AyahWord({this.arabic, this.translation, this.transliteration});

  /// The Arabic word as the source spells it.
  final String? arabic;

  /// What the source says this word means.
  final String? translation;

  /// Latin-script rendering of the word, when the source carries one.
  final String? transliteration;

  bool get hasArabic => (arabic ?? '').trim().isNotEmpty;
  bool get hasTranslation => (translation ?? '').trim().isNotEmpty;
  bool get hasTransliteration => (transliteration ?? '').trim().isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        if (arabic != null) 'arabic': arabic,
        if (translation != null) 'translation': translation,
        if (transliteration != null) 'transliteration': transliteration,
      };

  static AyahWord fromJson(Map<String, Object?> json) => AyahWord(
        arabic: _string(json['arabic']),
        translation: _string(json['translation']),
        transliteration: _string(json['transliteration']),
      );

  static String? _string(Object? value) {
    if (value is! String) return null;
    return value.trim().isEmpty ? null : value;
  }

  @override
  bool operator ==(Object other) =>
      other is AyahWord &&
      other.arabic == arabic &&
      other.translation == translation &&
      other.transliteration == transliteration;

  @override
  int get hashCode => Object.hash(arabic, translation, transliteration);

  @override
  String toString() => 'AyahWord($arabic, $translation)';
}
