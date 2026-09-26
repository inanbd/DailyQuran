import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../app/edition_providers.dart';
import '../../app/providers.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/entities/ayah.dart';
import '../../domain/entities/notification_preferences.dart';
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/reading_plan.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/entities/reading_track.dart';
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
    this.track = ReadingTrack.daily,
    this.hasPlan = false,
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

  /// Which reading is on screen: the Daily Ayah, or the plan.
  final ReadingTrack track;

  /// Whether the reader has a plan, and so a second reading to switch to.
  final bool hasPlan;

  bool get hasEdition => edition != null;

  /// Whether the plan's reading is the one on screen.
  bool get isPlan => track == ReadingTrack.plan;

  /// Where the reading on screen is stored. Null before an edition is open.
  String? get scope {
    final QuranEdition? open = edition;
    return open == null ? null : track.scopeFor(open.scope);
  }

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

    // The Daily Ayah and the plan are read separately, each from its own
    // scope. Changing to a *different* scope — another edition's, or the other
    // reading — drops any pinned browsing position; changing translation
    // within the same scope keeps it, which is the point of sharing a scope.
    final ReadingTrack track = preferences.activeTrack;
    final String scope = track.scopeFor(edition.scope);
    if (_pinnedScope != scope) {
      _pinnedScope = scope;
      _pinnedOrdinal = null;
    }

    ReadingProgress progress =
        await progressRepository.progressFor(scope, total);
    final int? firstUnread =
        await progressRepository.firstUnreadOrdinal(scope, total);

    final DateTime now = ref.watch(clockProvider)();

    // Each reading keeps its own day. The Daily Ayah rolls on with its
    // reminder, as it always has; a plan's goal is for the calendar day.
    final NotificationPreferences periods = track == ReadingTrack.plan
        ? PlanScheduler.calendarDays
        : ref.watch(notificationPreferencesProvider);

    // How much of this period's portion is already done. Counted from rows in
    // the read table rather than a running tally, so it stays right however the
    // reader moved about — ahead, back, or into another translation.
    final DateTime periodStart =
        ReminderSchedule(periods).currentPeriodStart(now);
    final int readThisPeriod =
        await progressRepository.readCountSince(scope, periodStart);

    final ReadingPortion portion = PlanScheduler.resolve(
      // The Daily Ayah is one ayah a period whatever the plan says.
      plan: track == ReadingTrack.plan ? preferences.plan : ReadingPlan.defaults,
      progress: progress,
      notificationPreferences: periods,
      readThisPeriod: readThisPeriod,
      now: now,
    );

    final int ordinal = _pinnedOrdinal ??
        ReadingScheduler.resolveTodaysOrdinal(
          progress: progress,
          firstUnreadOrdinal: firstUnread,
          notificationPreferences: periods,
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
      track: track,
      hasPlan: preferences.plan.isPaced,
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
    final String? scope = current?.scope;
    if (ayah == null || edition == null || scope == null) return;

    // Only the reading on screen is marked: an ayah read in the plan does not
    // count as the Daily Ayah, nor the other way round.
    final ProgressRepository repository = ref.read(progressRepositoryProvider);
    if (read) {
      await repository.markRead(
        scope,
        ayah.verseKey,
        ayah.ordinal,
        edition.totalAyah,
        at: ref.read(clockProvider)(),
      );
    } else {
      await repository.markUnread(
        scope,
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
  /// Called only on a tap of the Daily Ayah's reminder — a reminder firing on
  /// its own never changes progress, and a plan's reminder opens its goal
  /// instead. So it is always the Daily Ayah that is opened and marked, even
  /// if the plan was on screen last.
  Future<void> markReadFromNotification() async {
    await _show(ReadingTrack.daily);
    _pinnedOrdinal = null;
    ref.invalidateSelf();
    final TodayState refreshed = await future;
    if (refreshed.ayah == null || refreshed.isRead) return;
    await markRead();
  }

  /// Puts [track]'s reading on screen, at the place its own rule chooses.
  Future<void> switchTrack(ReadingTrack track) async {
    await _show(track);
    _pinnedOrdinal = null;
    ref.invalidateSelf();
    await future;
  }

  /// Remembers [track] as the reading to show, so it survives a restart.
  Future<void> _show(ReadingTrack track) async {
    final UserPreferences preferences = ref.read(userPreferencesProvider);
    if (preferences.readingTrack == track) return;
    await ref
        .read(userPreferencesProvider.notifier)
        .update(preferences.copyWith(readingTrack: track));
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
          current!.scope!,
          target,
          edition.totalAyah,
        );
    ref.invalidateSelf();
    await future;
  }

  /// Clears the reading on screen so it can begin again from the start.
  ///
  /// Only that reading: starting the plan over leaves the Daily Ayah where it
  /// was, and the other way round.
  Future<void> restart() async {
    final TodayState? current = state.value;
    final QuranEdition? edition = current?.edition;
    final String? scope = current?.scope;
    if (edition == null || scope == null) return;
    await ref
        .read(progressRepositoryProvider)
        .resetScope(scope, edition.totalAyah);

    // A plan starts its clock again too. Without this a fresh reading would
    // inherit a deadline most of which had already gone, and open on an
    // impossible first goal.
    if (current!.isPlan) await _savePlan(_rebaselined(_plan));
    await _reload();
  }

  // ---------------------------------------------------------------------------
  // The plan
  // ---------------------------------------------------------------------------

  ReadingPlan get _plan => ref.read(userPreferencesProvider).plan;

  /// Starts [plan], or changes the one already running to it.
  ///
  /// Changing pace keeps what the plan has read and measures the new pace from
  /// today. A plan started from none begins at the first ayah: a new plan is a
  /// new reading of the whole Qur'an, and must not inherit an old one's place.
  Future<void> choosePlan(ReadingPlan plan) async {
    final bool wasRunning = _plan.isPaced;
    if (!wasRunning) await _resetPlanReading();
    final UserPreferences preferences = ref.read(userPreferencesProvider);
    await ref.read(userPreferencesProvider.notifier).update(
          preferences.copyWith(
            plan: plan.copyWith(
              startedOn: ref.read(clockProvider)(),
              // Reminder settings belong to the reader, not to one plan, so a
              // new plan keeps the ones they already chose.
              reminderEnabled: _plan.reminderEnabled,
              reminderTime: _plan.reminderTime,
              needsTrackSeed: false,
            ),
            // Choosing a plan is choosing to read it.
            readingTrack: ReadingTrack.plan,
          ),
        );
    await ref.read(notificationPreferencesProvider.notifier).applyToScheduler();
    await _reload();
  }

  /// Measures the plan afresh from today, keeping everything it has read.
  ///
  /// The escape hatch a deadline needs: someone who put the reading down for
  /// two months picks it up again at a sane goal rather than an impossible one.
  /// A chosen-date plan moves to [targetDate] when one is given.
  Future<void> replanFromToday({DateTime? targetDate}) async {
    if (!_plan.isPaced) return;
    await _savePlan(
      _plan.copyWith(startedOn: ref.read(clockProvider)(), targetDate: targetDate),
    );
    await _reload();
  }

  /// Begins the plan again from the first ayah, measured from today.
  Future<void> restartPlan() async {
    if (!_plan.isPaced) return;
    await _resetPlanReading();
    await _savePlan(_rebaselined(_plan));
    await _reload();
  }

  /// Ends the plan and clears its reading. The Daily Ayah is untouched.
  Future<void> stopPlan() async {
    if (!_plan.isPaced) return;
    await _resetPlanReading();
    await _savePlan(
      _plan.copyWith(
        kind: ReadingPlanKind.oneAyah,
        clearStartedOn: true,
        clearTargetDate: true,
      ),
    );
    await _reload();
  }

  /// Turns the plan's own reminder on or off, or moves it.
  Future<void> setPlanReminder({bool? enabled, TimeOfDayValue? time}) =>
      _savePlan(_plan.copyWith(reminderEnabled: enabled, reminderTime: time));

  /// Clears the plan's reading for the edition open.
  Future<void> _resetPlanReading() async {
    final QuranEdition? edition = await _openEdition();
    if (edition == null) return;
    await ref.read(progressRepositoryProvider).resetScope(
          ReadingTrack.plan.scopeFor(edition.scope),
          edition.totalAyah,
        );
  }

  /// The edition being read, installed.
  Future<QuranEdition?> _openEdition() async {
    final QuranEdition? shown = state.value?.edition;
    if (shown != null) return shown;
    final String? id = ref.read(userPreferencesProvider).currentEditionId;
    if (id == null) return null;
    return ref.read(quranRepositoryProvider).installEdition(id);
  }

  /// [plan] measured from today.
  ///
  /// A chosen date that has already gone cannot be finished by. The new
  /// reading keeps the *length* of the journey the reader chose — the one thing
  /// about the old date that can survive it — while a date still ahead is kept
  /// as it stands.
  ReadingPlan _rebaselined(ReadingPlan plan) {
    final DateTime now = ref.read(clockProvider)();
    ReadingPlan next = plan.copyWith(startedOn: now);
    final DateTime? target = plan.targetDate;
    if (plan.kind == ReadingPlanKind.custom &&
        target != null &&
        !_dateOnly(target).isAfter(_dateOnly(now))) {
      final DateTime from = plan.startedOn ?? target;
      // Counted in UTC days so a DST transition inside the old window can
      // never shave a day off the new one.
      final int days = DateTime.utc(target.year, target.month, target.day)
          .difference(DateTime.utc(from.year, from.month, from.day))
          .inDays;
      next = next.copyWith(
        targetDate:
            DateTime(now.year, now.month, now.day + (days < 1 ? 30 : days)),
      );
    }
    return next;
  }

  /// Saves [plan] and re-arms reminders, which count out its goal.
  Future<void> _savePlan(ReadingPlan plan) async {
    final UserPreferences preferences = ref.read(userPreferencesProvider);
    await ref
        .read(userPreferencesProvider.notifier)
        .update(preferences.copyWith(plan: plan));
    await ref.read(notificationPreferencesProvider.notifier).applyToScheduler();
  }

  Future<void> _reload() async {
    _pinnedOrdinal = null;
    _invalidateProgressViews();
    ref.invalidateSelf();
    await future;
  }

  void _invalidateProgressViews() {
    ref.invalidate(libraryProvider);
    ref.invalidate(startedReadingsProvider);
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

final AsyncNotifierProvider<TodayController, TodayState> todayControllerProvider =
    AsyncNotifierProvider<TodayController, TodayState>(TodayController.new);
