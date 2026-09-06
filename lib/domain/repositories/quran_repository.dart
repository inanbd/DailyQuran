import '../entities/ayah.dart';
import '../entities/quran_edition.dart';
import '../entities/surah.dart';

/// Reads the Qur'an for the UI, backed by local storage so everything works
/// offline once an edition has been installed.
abstract interface class QuranRepository {
  /// All known editions, with `isInstalled` reflecting local storage.
  Future<List<QuranEdition>> editions();

  Future<QuranEdition?> edition(String editionId);

  /// Copies an edition's text from the content source into local storage.
  /// Safe to call repeatedly; already-installed editions are a no-op unless
  /// [force] is set.
  Future<QuranEdition> installEdition(String editionId, {bool force = false});

  /// The ayah at a 1-based reading position, or null when out of range.
  Future<Ayah?> ayahAt(String editionId, int ordinal);

  Future<Ayah?> ayahById(String ayahId);

  /// One ayah by its edition-independent key, e.g. `2:255`.
  ///
  /// This is how a favourite saved under one translation is rendered under
  /// another. Null when this edition has no such ayah.
  Future<Ayah?> ayahByVerseKey(String editionId, String verseKey);

  /// How many ayat are stored locally for an edition.
  Future<int> installedCount(String editionId);

  Future<List<Surah>> surahs(String editionId);

  /// The reading position of the first ayah of a surah, or null when nothing
  /// is stored against it.
  Future<int?> firstOrdinalOfSurah(String editionId, int surahNumber);
}
