import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/ayah.dart';
import '../../domain/entities/ayah_word.dart';
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/surah.dart';
import '../../domain/repositories/quran_content_source.dart';
import '../models/ayah_dto.dart';
import '../models/edition_dto.dart';
import 'content_schema.dart';

/// Reads Qur'an content from JSON bundled with the app.
///
/// An edition is "available" when its asset is present. The catalog can list
/// editions whose data has not been imported yet; those simply report `false`
/// from [hasContentFor] and the UI shows a dataset-not-installed state instead
/// of failing. Dropping an importer-generated file into
/// `assets/data/editions/` is all it takes to light one up.
class AssetQuranContentSource implements QuranContentSource {
  AssetQuranContentSource({this.bundle});

  /// Overrides the bundle assets are read from. Tests inject one; production
  /// leaves it null and reads from the app's root bundle.
  final AssetBundle? bundle;

  AssetBundle get _assets => bundle ?? rootBundle;

  /// The catalog and the surah index are both small and read repeatedly, so
  /// both are memoised. Edition files are megabytes once parsed and are needed
  /// only while an edition is being installed, so holding one for the life of
  /// the app would be pure waste.
  List<QuranEdition>? _catalogCache;
  List<Map<String, Object?>>? _surahIndexCache;
  Map<String, List<AyahWord>>? _wordIndexCache;

  @override
  Future<List<QuranEdition>> loadCatalog() async {
    final List<QuranEdition>? cached = _catalogCache;
    if (cached != null) return cached;

    final Map<String, Object?> json;
    try {
      json = await _readJson(ContentSchema.catalogAsset);
    } on Object catch (error) {
      throw CatalogUnavailableException(cause: error);
    }

    final Object? entries = json['editions'];
    if (entries is! List) {
      throw const CatalogUnavailableException();
    }

    final List<QuranEdition> editions = entries
        .whereType<Map<String, Object?>>()
        .map(EditionDto.fromJson)
        .toList(growable: false);
    _catalogCache = editions;
    return editions;
  }

  @override
  Future<bool> hasContentFor(String editionId) async {
    final QuranEdition? edition = await _editionById(editionId);
    if (edition == null) return false;
    try {
      await _readEditionFile(edition);
      return true;
    } on AppException {
      return false;
    }
  }

  @override
  Future<List<Ayah>> loadAyat(String editionId) async {
    final QuranEdition? edition = await _editionById(editionId);
    if (edition == null) throw DatasetUnavailableException(editionId);

    final Map<String, Object?> file = await _readEditionFile(edition);
    final Object? entries = file['ayat'];
    if (entries is! List) {
      throw ContentFormatException(
        'The data file for "$editionId" has no "ayat" list.',
      );
    }

    // Glosses are the same whichever translation is being read, so they come
    // from one shared index and are joined on here. An edition that carries its
    // own `words` keeps them: the parsed ayah already has them, and
    // `withWords` is only reached when it does not.
    final Map<String, List<AyahWord>> wordIndex = await _loadWordIndex();

    final String fallbackSource = edition.source.name;
    final List<Ayah> ayat = <Ayah>[];
    int ordinal = 0;
    for (final Object? entry in entries) {
      if (entry is! Map<String, Object?>) continue;
      ordinal++;
      final Ayah ayah = AyahDto.fromJson(
        entry,
        editionId: editionId,
        ordinal: ordinal,
        fallbackSource: fallbackSource,
      );
      ayat.add(
        ayah.hasWords
            ? ayah
            : ayah.withWords(wordIndex[ayah.verseKey] ?? const <AyahWord>[]),
      );
    }

    if (ayat.isEmpty) {
      throw DatasetUnavailableException(editionId);
    }
    return ayat;
  }

  /// Surah metadata for an edition.
  ///
  /// Names and lengths are the same for every complete edition of the Qur'an,
  /// so an edition file normally omits them and inherits the shared index that
  /// ships with the app. An edition whose surahs are *not* the Qur'an's — the
  /// development fixture — carries its own, and its own is always preferred.
  @override
  Future<List<Surah>> loadSurahs(String editionId) async {
    final QuranEdition? edition = await _editionById(editionId);
    if (edition == null) return const <Surah>[];

    List<Map<String, Object?>>? entries;
    try {
      final Map<String, Object?> file = await _readEditionFile(edition);
      final Object? own = file['surahs'];
      if (own is List) {
        entries = own.whereType<Map<String, Object?>>().toList(growable: false);
      }
    } on AppException {
      // No edition file yet. The shared index still describes the Qur'an, so
      // the surah list is worth showing.
    }

    entries ??= await _loadSurahIndex();
    return entries
        .map((Map<String, Object?> json) =>
            AyahDto.surahFromJson(json, editionId: editionId))
        .toList(growable: false);
  }

  /// The shared word index, keyed by verse key.
  ///
  /// A missing or unreadable index costs the word-by-word view and nothing
  /// else, so it resolves to an empty map rather than failing the install.
  Future<Map<String, List<AyahWord>>> _loadWordIndex() async {
    final Map<String, List<AyahWord>>? cached = _wordIndexCache;
    if (cached != null) return cached;

    final Map<String, List<AyahWord>> parsed = <String, List<AyahWord>>{};
    try {
      final Map<String, Object?> json =
          await _readJson(ContentSchema.wordByWordAsset);
      final Object? words = json['words'];
      if (words is Map<String, Object?>) {
        for (final MapEntry<String, Object?> entry in words.entries) {
          final List<AyahWord> value = AyahDto.wordsFromJson(entry.value);
          if (value.isNotEmpty) parsed[entry.key] = value;
        }
      }
    } on AppException {
      // No word index installed. The reading is unaffected.
    }
    _wordIndexCache = parsed;
    return parsed;
  }

  Future<List<Map<String, Object?>>> _loadSurahIndex() async {
    final List<Map<String, Object?>>? cached = _surahIndexCache;
    if (cached != null) return cached;

    final List<Map<String, Object?>> parsed;
    try {
      final Map<String, Object?> json =
          await _readJson(ContentSchema.surahIndexAsset);
      final Object? entries = json['surahs'];
      parsed = entries is List
          ? entries.whereType<Map<String, Object?>>().toList(growable: false)
          : const <Map<String, Object?>>[];
    } on AppException {
      // A missing index costs the surah list, not the reading.
      return const <Map<String, Object?>>[];
    }
    _surahIndexCache = parsed;
    return parsed;
  }

  Future<QuranEdition?> _editionById(String editionId) async {
    final List<QuranEdition> catalog = await loadCatalog();
    for (final QuranEdition edition in catalog) {
      if (edition.id == editionId) return edition;
    }
    return null;
  }

  Future<Map<String, Object?>> _readEditionFile(QuranEdition edition) =>
      _readJson(ContentSchema.assetForSlug(edition.slug));

  Future<Map<String, Object?>> _readJson(String asset) async {
    final String raw;
    try {
      raw = await _assets.loadString(asset);
    } on Object catch (error) {
      throw ContentFormatException('Missing asset "$asset".', cause: error);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw ContentFormatException('"$asset" is not valid JSON.', cause: error);
    }
    if (decoded is! Map<String, Object?>) {
      throw ContentFormatException('"$asset" must contain a JSON object.');
    }
    return decoded;
  }

  /// Drops the memoised catalog and surah index, so newly added content is
  /// picked up without a restart.
  void clearCache() {
    _catalogCache = null;
    _surahIndexCache = null;
    _wordIndexCache = null;
  }
}
