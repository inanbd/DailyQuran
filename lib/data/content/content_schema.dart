/// The JSON contract between the app and whatever produces Qur'an text.
///
/// Anything that can emit these shapes — a bundled asset, an HTTP API, a
/// publisher's export — can back the app without a single UI change. The
/// importer in `tool/import_quran.dart` writes exactly this format.
abstract final class ContentSchema {
  /// Bumped whenever the on-disk shape changes incompatibly.
  static const int version = 1;

  /// Asset path of the edition catalog.
  static const String catalogAsset = 'assets/data/catalog.json';

  /// The shared surah index: names, lengths and classification for all 114
  /// surahs. Reference data, not Qur'an text, so it ships with the app and the
  /// surah list works before any edition has been imported.
  static const String surahIndexAsset = 'assets/data/surahs.json';

  /// Directory holding one JSON file per edition.
  static const String editionsDirectory = 'assets/data/editions';

  static String assetForSlug(String slug) => '$editionsDirectory/$slug.json';
}
