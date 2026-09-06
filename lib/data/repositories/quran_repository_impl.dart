import '../../core/errors/app_exception.dart';
import '../../domain/entities/ayah.dart';
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/surah.dart';
import '../../domain/repositories/quran_content_source.dart';
import '../../domain/repositories/quran_repository.dart';
import '../local/ayah_dao.dart';

/// Bridges the content source and local storage.
///
/// The content source is consulted once per edition, at install time;
/// everything the UI reads afterwards comes from SQLite. That is what makes the
/// reading experience work with no network and makes swapping the content
/// source invisible to the rest of the app.
class QuranRepositoryImpl implements QuranRepository {
  QuranRepositoryImpl({required this.contentSource, required this.dao});

  /// Where Qur'an text comes from. Swapping this changes the data provider for
  /// the whole app.
  final QuranContentSource contentSource;

  /// Local storage the text is copied into.
  final AyahDao dao;

  @override
  Future<List<QuranEdition>> editions() async {
    final List<QuranEdition> catalog = await contentSource.loadCatalog();
    final Set<String> installed = await dao.installedEditionIds();

    final List<QuranEdition> result = <QuranEdition>[];
    for (final QuranEdition edition in catalog) {
      if (installed.contains(edition.id)) {
        final int count = await dao.countFor(edition.id);
        result.add(
          edition.copyWith(
            isInstalled: true,
            isAvailable: true,
            // Trust what is actually stored over the catalog's stated total, so
            // progress is never measured against a count we do not have.
            totalAyah: count > 0 ? count : edition.totalAyah,
          ),
        );
      } else {
        result.add(
          edition.copyWith(
            isInstalled: false,
            isAvailable: await contentSource.hasContentFor(edition.id),
          ),
        );
      }
    }
    return result;
  }

  @override
  Future<QuranEdition?> edition(String editionId) async {
    final List<QuranEdition> all = await editions();
    for (final QuranEdition candidate in all) {
      if (candidate.id == editionId) return candidate;
    }
    return null;
  }

  @override
  Future<QuranEdition> installEdition(
    String editionId, {
    bool force = false,
  }) async {
    final QuranEdition? catalogEntry = await _catalogEntry(editionId);
    if (catalogEntry == null) {
      throw DatasetUnavailableException(editionId);
    }

    if (!force) {
      final int existing = await dao.countFor(editionId);
      if (existing > 0) {
        return catalogEntry.copyWith(
          isInstalled: true,
          isAvailable: true,
          totalAyah: existing,
        );
      }
    }

    final List<Ayah> ayat = await contentSource.loadAyat(editionId);
    final List<Surah> surahs = await contentSource.loadSurahs(editionId);
    await dao.replaceEdition(editionId, catalogEntry.slug, ayat, surahs);
    return catalogEntry.copyWith(
      isInstalled: true,
      isAvailable: true,
      totalAyah: ayat.length,
    );
  }

  @override
  Future<Ayah?> ayahAt(String editionId, int ordinal) {
    if (ordinal < 1) return Future<Ayah?>.value();
    return dao.byOrdinal(editionId, ordinal);
  }

  @override
  Future<Ayah?> ayahById(String ayahId) => dao.byId(ayahId);

  @override
  Future<Ayah?> ayahByVerseKey(String editionId, String verseKey) =>
      dao.byVerseKey(editionId, verseKey);

  @override
  Future<int> installedCount(String editionId) => dao.countFor(editionId);

  @override
  Future<List<Surah>> surahs(String editionId) => dao.surahs(editionId);

  @override
  Future<int?> firstOrdinalOfSurah(String editionId, int surahNumber) =>
      dao.firstOrdinalOfSurah(editionId, surahNumber);

  Future<QuranEdition?> _catalogEntry(String editionId) async {
    final List<QuranEdition> catalog = await contentSource.loadCatalog();
    for (final QuranEdition edition in catalog) {
      if (edition.id == editionId) return edition;
    }
    return null;
  }
}
