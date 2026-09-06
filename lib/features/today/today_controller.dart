import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../app/edition_providers.dart';
import '../../app/providers.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/entities/ayah.dart';
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/entities/user_preferences.dart';
import '../../domain/repositories/progress_repository.dart';
import '../../domain/repositories/quran_repository.dart';
import '../../domain/services/reading_scheduler.dart';

/// What the Today screen renders.
@immutable
class TodayState {
  const TodayState({
    this.edition,
    this.ayah,
    this.progress,
    this.isRead = false,
  });

  /// No edition chosen yet.
  static const TodayState empty = TodayState();

  final QuranEdition? edition;

  /// The ayah on screen. Null when the reading is finished or nothing is
  /// chosen.
  final Ayah? ayah;

  final ReadingProgress? progress;

  /// Whether [ayah] is marked read.
  final bool isRead;

  bool get hasEdition => edition != null;

  /// True once every ayah in the edition has been read.
  bool get isComplete => progress?.isComplete ?? false;

  int get ordinal => ayah?.ordinal ?? progress?.currentOrdinal ?? 1;

  int get total => progress?.totalAyah ?? edition?.totalAyah ?? 0;

  bool get hasPrevious => ordinal > 1;

  bool get hasNext => ordinal < total;
}

/// Drives the Today screen.
///
/// Position rules live in [ReadingScheduler]; this controller only decides
/// *when* to apply them. Browsing with Previous/Next pins a position for the
/// session so a rebuild cannot yank the reader back, while a genuine refresh
/// (app resume, notification tap) lets the reading roll forward normally.
class TodayController extends AsyncNotifier<TodayState> {
  int? _pinnedOrdinal;
  String? _pinnedScope;

  @override
  Future<TodayState> build() async {
    final UserPreferences preferences = ref.watch(userPreferencesProvider);
    final String? editionId = preferences.currentEditionId;

    if (editionId == null) return TodayState.empty;

    final QuranRepository quranRepository = ref.watch(quranRepositoryProvider);
    final ProgressRepository progressRepository =
        ref.watch(progressRepositoryProvider);

    // First open of an edition copies it into local storage; afterwards this is
    // a cheap no-op.
    final QuranEdition edition = await quranRepository.installEdition(editionId);
    final int total = edition.totalAyah;
    if (total <= 0) throw DatasetUnavailableException(editionId);

    // Changing to an edition in a *different* scope drops any pinned browsing
    // position; changing translation within the same scope keeps it, which is
    // the point of sharing a scope at all.
    final String scope = edition.scope;
    if (_pinnedScope != scope) {
      _pinnedScope = scope;
      _pinnedOrdinal = null;
    }

    ReadingProgress progress =
        await progressRepository.progressFor(scope, total);
    final int? firstUnread =
        await progressRepository.firstUnreadOrdinal(scope, total);

    final int ordinal = _pinnedOrdinal ??
        ReadingScheduler.resolveTodaysOrdinal(
          progress: progress,
          firstUnreadOrdinal: firstUnread,
          notificationPreferences: ref.watch(notificationPreferencesProvider),
          now: ref.watch(clockProvider)(),
        );

    if (ordinal != progress.currentOrdinal) {
      progress =
          await progressRepository.setCurrentOrdinal(scope, ordinal, total);
    }

    final Ayah? ayah = await quranRepository.ayahAt(editionId, ordinal);
    final bool isRead =
        ayah != null && await progressRepository.isRead(scope, ayah.verseKey);

    return TodayState(
      edition: edition,
      ayah: ayah,
      progress: progress,
      isRead: isRead,
    );
  }

  /// Re-reads everything and lets the position roll forward if a new reading
  /// period has begun. Called on app resume and on notification taps.
  Future<void> refresh() async {
    _pinnedOrdinal = null;
    ref.invalidateSelf();
    await future;
  }

  /// Marks the ayah on screen as read. Only this one — never a range.
  Future<void> markRead() => _setRead(true);

  Future<void> markUnread() => _setRead(false);

  Future<void> _setRead(bool read) async {
    final TodayState? current = state.value;
    final Ayah? ayah = current?.ayah;
    final QuranEdition? edition = current?.edition;
    if (ayah == null || edition == null) return;

    final ProgressRepository repository = ref.read(progressRepositoryProvider);
    if (read) {
      await repository.markRead(
        edition.scope,
        ayah.verseKey,
        ayah.ordinal,
        edition.totalAyah,
        at: ref.read(clockProvider)(),
      );
    } else {
      await repository.markUnread(
        edition.scope,
        ayah.verseKey,
        edition.totalAyah,
      );
    }

    // Hold the reader on the ayah they just acted on.
    _pinnedOrdinal = ayah.ordinal;
    _invalidateProgressViews();
    ref.invalidateSelf();
    await future;
  }

  /// Marks today's ayah read because the reader arrived from a reminder.
  ///
  /// Called only on a notification tap — a reminder firing on its own never
  /// changes progress.
  Future<void> markReadFromNotification() async {
    _pinnedOrdinal = null;
    ref.invalidateSelf();
    final TodayState refreshed = await future;
    if (refreshed.ayah == null || refreshed.isRead) return;
    await markRead();
  }

  Future<void> goToNext() async {
    final TodayState? current = state.value;
    if (current == null || !current.hasNext) return;
    await _moveTo(current.ordinal + 1);
  }

  Future<void> goToPrevious() async {
    final TodayState? current = state.value;
    if (current == null || !current.hasPrevious) return;
    await _moveTo(current.ordinal - 1);
  }

  /// Jumps to a specific position, e.g. the start of a surah.
  Future<void> goTo(int ordinal) => _moveTo(ordinal);

  Future<void> _moveTo(int ordinal) async {
    final TodayState? current = state.value;
    final QuranEdition? edition = current?.edition;
    if (edition == null) return;
    final int target = ordinal.clamp(1, edition.totalAyah);

    // Moving through the mushaf is browsing, not reading: nothing in between is
    // marked read, and the position sticks until the next refresh.
    _pinnedOrdinal = target;
    await ref.read(progressRepositoryProvider).setCurrentOrdinal(
          edition.scope,
          target,
          edition.totalAyah,
        );
    ref.invalidateSelf();
    await future;
  }

  /// Clears read state so a finished reading can begin again from the start.
  Future<void> restart() async {
    final QuranEdition? edition = state.value?.edition;
    if (edition == null) return;
    await ref
        .read(progressRepositoryProvider)
        .resetScope(edition.scope, edition.totalAyah);
    _pinnedOrdinal = null;
    _invalidateProgressViews();
    ref.invalidateSelf();
    await future;
  }

  void _invalidateProgressViews() {
    ref.invalidate(libraryProvider);
    ref.invalidate(startedReadingsProvider);
  }
}

final AsyncNotifierProvider<TodayController, TodayState> todayControllerProvider =
    AsyncNotifierProvider<TodayController, TodayState>(TodayController.new);
