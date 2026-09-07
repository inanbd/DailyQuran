import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../app/edition_providers.dart';
import '../../app/providers.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/entities/ayah.dart';
import '../../domain/entities/notification_preferences.dart';
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/entities/user_preferences.dart';
import '../../domain/repositories/progress_repository.dart';
import '../../domain/repositories/quran_repository.dart';
import '../../domain/services/plan_scheduler.dart';
import '../../domain/services/reading_scheduler.dart';
import '../../domain/services/reminder_schedule.dart';

/// What the Today screen renders.
@immutable
class TodayState {
  const TodayState({
    this.edition,
    this.ayah,
    this.secondaryEdition,
    this.secondaryAyah,
    this.progress,
    this.portion,
    this.isRead = false,
  });

  /// No edition chosen yet.
  static const TodayState empty = TodayState();

  final QuranEdition? edition;

  /// The ayah on screen. Null when the reading is finished or nothing is
  /// chosen.
  final Ayah? ayah;

  /// The second translation, when the reader has asked for one.
  final QuranEdition? secondaryEdition;

  /// The same ayah in [secondaryEdition]. Null when there is no second
  /// translation, and also when that edition simply has no text for this ayah —
  /// a gap in one translation must not blank the page.
  final Ayah? secondaryAyah;

  /// Whether a second translation is on screen with text to show.
  bool get hasSecondTranslation =>
      secondaryEdition != null && (secondaryAyah?.hasTranslation ?? false);

  final ReadingProgress? progress;

  /// What this reading period asks for, and how much of it is done.
  final ReadingPortion? portion;

  /// Whether [ayah] is marked read.
  final bool isRead;

  bool get hasEdition => edition != null;

  /// Whether the plan asks for more than one ayah a period. The portion counter
  /// is worth showing only when there is a portion to count through.
  bool get hasPortion => (portion?.target ?? 1) > 1;

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

    final NotificationPreferences notificationPreferences =
        ref.watch(notificationPreferencesProvider);
    final DateTime now = ref.watch(clockProvider)();

    // How much of this period's portion is already done. Counted from rows in
    // the read table rather than a running tally, so it stays right however the
    // reader moved about — ahead, back, or into another translation.
    final DateTime periodStart =
        ReminderSchedule(notificationPreferences).currentPeriodStart(now);
    final int readThisPeriod =
        await progressRepository.readCountSince(scope, periodStart);

    final ReadingPortion portion = PlanScheduler.resolve(
      plan: preferences.plan,
      progress: progress,
      notificationPreferences: notificationPreferences,
      readThisPeriod: readThisPeriod,
      now: now,
    );

    final int ordinal = _pinnedOrdinal ??
        ReadingScheduler.resolveTodaysOrdinal(
          progress: progress,
          firstUnreadOrdinal: firstUnread,
          notificationPreferences: notificationPreferences,
          now: now,
          portionComplete: portion.isComplete,
        );

    if (ordinal != progress.currentOrdinal) {
      progress =
          await progressRepository.setCurrentOrdinal(scope, ordinal, total);
    }

    final Ayah? ayah = await quranRepository.ayahAt(editionId, ordinal);
    final bool isRead =
        ayah != null && await progressRepository.isRead(scope, ayah.verseKey);

    final (QuranEdition?, Ayah?) second = await _loadSecond(
      quranRepository: quranRepository,
      secondaryId: preferences.secondaryEditionId,
      primaryId: editionId,
      scope: scope,
      ordinal: ordinal,
    );

    return TodayState(
      edition: edition,
      ayah: ayah,
      secondaryEdition: second.$1,
      secondaryAyah: second.$2,
      progress: progress,
      portion: portion,
      isRead: isRead,
    );
  }

  /// The second translation of the ayah on screen, if one is set up.
  ///
  /// Returns nothing rather than throwing whatever goes wrong here. A second
  /// translation is an extra reading of an ayah the reader can already see, so
  /// a missing dataset, a different numbering, or an ayah that edition does not
  /// carry must cost that extra reading and never the page itself.
  Future<(QuranEdition?, Ayah?)> _loadSecond({
    required QuranRepository quranRepository,
    required String? secondaryId,
    required String primaryId,
    required String scope,
    required int ordinal,
  }) async {
    if (secondaryId == null || secondaryId == primaryId) {
      return (null, null);
    }
    try {
      final QuranEdition second =
          await quranRepository.installEdition(secondaryId);
      // Ordinals only line up between editions counting the same ayat. Anything
      // else would put an unrelated ayah under this one, which is worse than
      // showing no second translation at all.
      if (second.scope != scope) return (null, null);
      return (second, await quranRepository.ayahAt(secondaryId, ordinal));
    } on AppException {
      return (null, null);
    }
  }

  /// Re-reads everything and lets the position roll forward if a new reading
  /// period has begun. Called on app resume and on notification taps.
  Future<void> refresh() async {
    _pinnedOrdinal = null;
    ref.invalidateSelf();
    await future;
  }

  /// Marks the ayah on screen as read and, when the plan is still asking for
  /// more this period, brings the next one. Only this ayah is ever marked —
  /// never a range.
  Future<void> markRead() => _setRead(true, advance: true);

  /// Marks the ayah read without moving off it.
  ///
  /// What auto-marking uses. Advancing on a dwell timer would walk a reader
  /// through a whole portion unattended — every ayah short enough to fit on
  /// screen would mark and turn itself five seconds later — so reading one
  /// through marks it and stops there.
  Future<void> markReadInPlace() => _setRead(true, advance: false);

  Future<void> markUnread() => _setRead(false, advance: false);

  Future<void> _setRead(bool read, {required bool advance}) async {
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

    // Advancing means handing the choice back to the reading rule, which holds
    // position once the portion is finished and moves to the next unread ayah
    // while it is not. Otherwise the reader stays exactly where they acted.
    _pinnedOrdinal = advance ? null : ayah.ordinal;
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

    // A plan working towards a date starts its clock again too. Without this a
    // fresh reading would inherit a deadline most of which had already gone,
    // and open on an impossible first portion.
    final UserPreferences preferences = ref.read(userPreferencesProvider);
    if (preferences.plan.isPaced) {
      await ref.read(userPreferencesProvider.notifier).update(
            preferences.copyWith(
              plan: preferences.plan.copyWith(
                startedOn: ref.read(clockProvider)(),
              ),
            ),
          );
    }

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
