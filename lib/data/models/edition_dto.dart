import '../../core/errors/app_exception.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/quran_edition.dart';

/// Parses catalog entries into [QuranEdition]s.
abstract final class EditionDto {
  static QuranEdition fromJson(Map<String, Object?> json) {
    final String? id = json['id'] as String?;
    if (id == null || id.isEmpty) {
      throw const ContentFormatException(
        'A catalog entry is missing its "id".',
      );
    }
    final String slug = (json['slug'] as String?) ?? id;
    return QuranEdition(
      id: id,
      slug: slug,
      titleEnglish: (json['titleEnglish'] as String?) ?? id,
      titleArabic: (json['titleArabic'] as String?) ?? '',
      translator: (json['translator'] as String?) ?? '',
      translatorArabic: json['translatorArabic'] as String?,
      description: (json['description'] as String?) ?? '',
      languageName: (json['languageName'] as String?) ?? 'English',
      languageCode: (json['languageCode'] as String?) ?? 'en-US',
      isRightToLeft:
          (json['languageDirection'] as String?)?.toLowerCase() == 'rtl',
      totalAyah: _asInt(json['totalAyah']) ?? 0,
      // Absent means the edition stands alone. Complete editions of the Qur'an
      // declare a shared scope so a change of translation keeps the reader's
      // place; the development fixture deliberately does not.
      progressScope: json['progressScope'] as String?,
      verification:
          ContentVerification.fromStorage(json['verification'] as String?),
      source: sourceFromJson(json['source']),
    );
  }

  static ContentSource sourceFromJson(Object? raw) {
    if (raw is! Map<String, Object?>) {
      return const ContentSource(name: 'Unattributed');
    }
    final String? retrieved = raw['retrievedAt'] as String?;
    return ContentSource(
      name: (raw['name'] as String?) ?? 'Unattributed',
      url: raw['url'] as String?,
      translator: raw['translator'] as String?,
      licence: raw['licence'] as String?,
      retrievedAt: retrieved == null ? null : DateTime.tryParse(retrieved),
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
