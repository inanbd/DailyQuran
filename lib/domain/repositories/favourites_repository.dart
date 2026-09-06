import '../entities/favourite_ayah.dart';

/// Saved ayat.
///
/// Favourites are the reader's own data: nothing here is derived from reading
/// progress, and re-importing an edition never clears them. They are keyed by
/// verse key, so they survive a change of translation.
abstract interface class FavouritesRepository {
  /// Every favourite, most recently saved first, with its text resolved in
  /// [editionId].
  ///
  /// Entries the edition has no text for are skipped rather than surfaced as
  /// blanks — the row stays, so it reappears under an edition that has them.
  Future<List<FavouriteAyah>> all(String editionId);

  Future<bool> isFavourite(String scope, String verseKey);

  /// Adds or removes [verseKey], returning whether it is a favourite after
  /// the change.
  Future<bool> toggle(String scope, String verseKey, int ordinal);

  Future<int> count();
}
