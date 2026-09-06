import '../../domain/entities/ayah.dart';
import '../../domain/entities/favourite_ayah.dart';
import '../../domain/repositories/favourites_repository.dart';
import '../local/ayah_dao.dart';
import '../local/favourites_dao.dart';

class FavouritesRepositoryImpl implements FavouritesRepository {
  FavouritesRepositoryImpl({required this.favouritesDao, required this.ayahDao});

  /// Saved-ayah rows, keyed by verse key.
  final FavouritesDao favouritesDao;

  /// Local storage the saved text is read back from.
  final AyahDao ayahDao;

  @override
  Future<List<FavouriteAyah>> all(String editionId) async {
    final List<FavouriteRecord> records = await favouritesDao.all();
    final List<FavouriteAyah> result = <FavouriteAyah>[];
    for (final FavouriteRecord record in records) {
      // Resolved against the edition being read, so a saved ayah is always
      // shown in the translation the reader is on now. An edition that has no
      // text for it is skipped; the row is left alone, so it returns under one
      // that does.
      final Ayah? ayah = await ayahDao.byVerseKey(editionId, record.verseKey);
      if (ayah == null) continue;
      result.add(FavouriteAyah(ayah: ayah, savedAt: record.savedAt));
    }
    return result;
  }

  @override
  Future<bool> isFavourite(String scope, String verseKey) =>
      favouritesDao.isFavourite(scope, verseKey);

  @override
  Future<bool> toggle(String scope, String verseKey, int ordinal) async {
    final bool wasFavourite = await favouritesDao.isFavourite(scope, verseKey);
    if (wasFavourite) {
      await favouritesDao.remove(scope, verseKey);
      return false;
    }
    await favouritesDao.add(scope, verseKey, ordinal);
    return true;
  }

  @override
  Future<int> count() => favouritesDao.count();
}
