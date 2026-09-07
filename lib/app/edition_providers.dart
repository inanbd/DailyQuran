import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../domain/entities/quran_edition.dart';
import '../domain/entities/reading_progress.dart';
import '../domain/entities/surah.dart';
import '../domain/entities/user_preferences.dart';
import '../domain/repositories/progress_repository.dart';
import '../domain/repositories/quran_repository.dart';
import 'providers.dart';

/// Every edition in the catalog, with local install state resolved.
final FutureProvider<List<QuranEdition>> editionsProvider =
    FutureProvider<List<QuranEdition>>(
  (Ref ref) => ref.watch(quranRepositoryProvider).editions(),
);

/// The editions offered to the reader for browsing and selection, A-Z by
/// translation name.
///
/// The development fixture is placeholder text rather than the Qur'an, so it is
/// hidden as soon as any verified edition is readable. It stays listed while it
/// is the only readable content: a fresh checkout ships the fixture alone, and
/// hiding it there would leave nothing to read until an edition is imported.
///
/// Alphabetical rather than catalog order, which is an accident of when each
/// edition was added and gives the reader no way to predict where a
/// translation will be. Sorted here rather than in each screen so the
/// Translations page and the one-tap chooser can never disagree.
final FutureProvider<List<QuranEdition>> browsableEditionsProvider =
    FutureProvider<List<QuranEdition>>((Ref ref) async {
  final List<QuranEdition> editions =
      await ref.watch(editionsProvider.future);

  final bool hasVerifiedContent = editions.any(
    (QuranEdition edition) => edition.isReadable && !edition.isFixture,
  );
  final List<QuranEdition> browsable = hasVerifiedContent
      ? editions.where((QuranEdition edition) => !edition.isFixture).toList()
      : editions.toList();

  browsable.sort(
    (QuranEdition a, QuranEdition b) =>
        a.titleEnglish.toLowerCase().compareTo(b.titleEnglish.toLowerCase()),
  );
  return browsable;
});

/// An edition paired with the reader's progress through it.
@immutable
class LibraryEntry {
  const LibraryEntry({required this.edition, required this.progress});

  final QuranEdition edition;
  final ReadingProgress progress;

  bool get hasStarted => progress.hasStarted || progress.totalRead > 0;
}

/// The library list in [browsableEditionsProvider]'s A-Z order, each entry
/// carrying its own progress.
final FutureProvider<List<LibraryEntry>> libraryProvider =
    FutureProvider<List<LibraryEntry>>((Ref ref) async {
  final List<QuranEdition> editions =
      await ref.watch(browsableEditionsProvider.future);
  final ProgressRepository progressRepository =
      ref.watch(progressRepositoryProvider);

  final List<LibraryEntry> entries = <LibraryEntry>[];
  for (final QuranEdition edition in editions) {
    entries.add(
      LibraryEntry(
        edition: edition,
        progress:
            await progressRepository.progressFor(edition.scope, edition.totalAyah),
      ),
    );
  }
  return entries;
});

/// Only the reading the reader has actually started, most recent first.
/// Backs the Progress screen.
///
/// One row per *scope*, not per edition: every complete edition of the Qur'an
/// shares one, so listing them all would repeat the same progress under a
/// different translator's name. The reader's current edition represents its
/// scope where it can.
final FutureProvider<List<LibraryEntry>> startedReadingsProvider =
    FutureProvider<List<LibraryEntry>>((Ref ref) async {
  final List<LibraryEntry> entries = await ref.watch(libraryProvider.future);
  final String? currentId = ref.watch(
    userPreferencesProvider
        .select((UserPreferences prefs) => prefs.currentEditionId),
  );

  final Map<String, LibraryEntry> byScope = <String, LibraryEntry>{};
  for (final LibraryEntry entry in entries) {
    if (!entry.hasStarted) continue;
    final String scope = entry.edition.scope;
    final LibraryEntry? held = byScope[scope];
    if (held == null || entry.edition.id == currentId) {
      byScope[scope] = entry;
    }
  }

  final List<LibraryEntry> started = byScope.values.toList();
  started.sort((LibraryEntry a, LibraryEntry b) {
    final DateTime? left = a.progress.lastReadAt;
    final DateTime? right = b.progress.lastReadAt;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
  });
  return started;
});

/// A single edition by id, or null when the catalog has no such entry.
final editionProvider = FutureProvider.family<QuranEdition?, String>(
  (Ref ref, String id) async {
    final List<QuranEdition> editions =
        await ref.watch(editionsProvider.future);
    for (final QuranEdition edition in editions) {
      if (edition.id == id) return edition;
    }
    return null;
  },
);

/// Progress for a single edition, read from the scope it belongs to.
final editionProgressProvider =
    FutureProvider.family<ReadingProgress, String>((Ref ref, String id) async {
  final QuranEdition? edition = await ref.watch(editionProvider(id).future);
  return ref.watch(progressRepositoryProvider).progressFor(
        edition?.scope ?? id,
        edition?.totalAyah ?? 0,
      );
});

/// The edition the Today screen reads from.
final FutureProvider<QuranEdition?> currentEditionProvider =
    FutureProvider<QuranEdition?>((Ref ref) async {
  final String? id = ref.watch(
    userPreferencesProvider
        .select((UserPreferences prefs) => prefs.currentEditionId),
  );
  if (id == null) return null;
  return ref.watch(editionProvider(id).future);
});

/// The second translation shown under the first, or null for just the one.
final FutureProvider<QuranEdition?> secondaryEditionProvider =
    FutureProvider<QuranEdition?>((Ref ref) async {
  final String? id = ref.watch(
    userPreferencesProvider
        .select((UserPreferences prefs) => prefs.secondaryEditionId),
  );
  if (id == null) return null;
  return ref.watch(editionProvider(id).future);
});

/// The progress scope of the edition being read, for the screens that store
/// against it. Null before an edition has been chosen.
final FutureProvider<String?> currentScopeProvider =
    FutureProvider<String?>((Ref ref) async {
  final QuranEdition? edition = await ref.watch(currentEditionProvider.future);
  return edition?.scope;
});

/// The surahs of an edition.
///
/// Surah metadata is reference data rather than Qur'an text, so a complete
/// edition inherits the index that ships with the app and the list is available
/// as soon as the edition is installed.
final surahsProvider = FutureProvider.family<List<Surah>, String>((
  Ref ref,
  String editionId,
) async {
  final QuranRepository repository = ref.watch(quranRepositoryProvider);
  // A no-op once the edition is installed, but it guarantees surahs are never
  // read from a half-copied edition on first open.
  await repository.installEdition(editionId);
  return repository.surahs(editionId);
});
