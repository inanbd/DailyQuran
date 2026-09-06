import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/ayah.dart';
import '../domain/entities/favourite_ayah.dart';
import '../domain/entities/quran_edition.dart';
import '../domain/repositories/favourites_repository.dart';
import 'edition_providers.dart';
import 'providers.dart';

/// Every saved ayah, newest first, rendered in the edition being read.
///
/// Saved ayat are stored by verse key, so their text has to be resolved out of
/// the edition currently open. That edition is installed first: a reader who
/// changes translation and comes straight here would otherwise be shown an
/// empty list, because the new edition has no rows in local storage yet.
/// Installing is a no-op once it has happened.
final FutureProvider<List<FavouriteAyah>> favouritesProvider =
    FutureProvider<List<FavouriteAyah>>((Ref ref) async {
  final QuranEdition? edition = await ref.watch(currentEditionProvider.future);
  if (edition == null) return const <FavouriteAyah>[];
  await ref.watch(quranRepositoryProvider).installEdition(edition.id);
  return ref.watch(favouritesRepositoryProvider).all(edition.id);
});

/// Whether one ayah is saved. Keyed by the ayah, whose verse key and scope are
/// what the row is actually stored under.
final isFavouriteProvider = FutureProvider.family<bool, Ayah>(
  (Ref ref, Ayah ayah) async {
    final String? scope = await ref.watch(currentScopeProvider.future);
    if (scope == null) return false;
    return ref
        .watch(favouritesRepositoryProvider)
        .isFavourite(scope, ayah.verseKey);
  },
);

/// Adds and removes favourites, invalidating the list so every screen showing
/// a heart updates at once.
class FavouritesController extends Notifier<void> {
  @override
  void build() {}

  Future<bool> toggle(Ayah ayah) async {
    final String? scope = await ref.read(currentScopeProvider.future);
    if (scope == null) return false;

    final FavouritesRepository repository =
        ref.read(favouritesRepositoryProvider);
    final bool nowFavourite =
        await repository.toggle(scope, ayah.verseKey, ayah.ordinal);
    ref.invalidate(favouritesProvider);
    ref.invalidate(isFavouriteProvider(ayah));
    return nowFavourite;
  }
}

final NotifierProvider<FavouritesController, void> favouritesControllerProvider =
    NotifierProvider<FavouritesController, void>(FavouritesController.new);
