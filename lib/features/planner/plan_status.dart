import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/entities/ayah.dart';
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/reading_plan.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/entities/reading_track.dart';
import '../../domain/entities/user_preferences.dart';
import '../../domain/repositories/progress_repository.dart';
import '../../domain/services/plan_scheduler.dart';
import '../../domain/services/reminder_schedule.dart';
import '../today/today_controller.dart';

/// How a plan is going, in the handful of states worth telling a reader.
enum PlanStanding {
  /// The whole Qur'an has been read.
  complete,

  /// Today's goal has been read.
  doneToday,

  /// The finish date has gone with reading still to do.
  late,

  /// Behind: today's goal is bigger than usual to catch up.
  behind,

  /// Ahead: today's goal is smaller than usual.
  ahead,

  onTrack,
}

/// Where the reader's plan stands today.
///
/// Read from the plan's own track, so it describes the plan whichever reading
/// the Today screen happens to be showing.
@immutable
class PlanStatus {
  const PlanStatus({
    required this.plan,
    required this.edition,
    required this.progress,
    required this.goal,
    required this.today,
    this.nextAyah,
  });

  final ReadingPlan plan;
  final QuranEdition edition;

  /// The plan's reading of the whole Qur'an.
  final ReadingProgress progress;

  /// Today's goal, and how much of it is read.
  final ReadingPortion goal;

  /// The calendar day this describes.
  final DateTime today;

  /// Where the plan's reading carries on from, when there is any left.
  final Ayah? nextAyah;

  /// The day the plan is working towards.
  DateTime? get finishDate => goal.deadline;

  /// Days left to read in, today included. Zero once the date has gone.
  int get daysLeft {
    final DateTime? finish = finishDate;
    if (finish == null) return 0;
    final int days = _epochDay(finish) - _epochDay(today) + 1;
    return days < 0 ? 0 : days;
  }

  PlanStanding get standing {
    if (progress.isComplete) return PlanStanding.complete;
    if (goal.isComplete) return PlanStanding.doneToday;
    final DateTime? projected = goal.projectedCompletion;
    if (projected != null && projected != goal.deadline) {
      return PlanStanding.late;
    }
    if (goal.isCatchingUp || goal.periodsBehind > 0) {
      return PlanStanding.behind;
    }
    if (goal.isAhead) return PlanStanding.ahead;
    return PlanStanding.onTrack;
  }

  static int _epochDay(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day).millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay;
}

/// The reader's plan, or null when they have none.
///
/// Built on the Today controller's edition rather than installing one itself,
/// and rebuilt whenever that controller is — which is every time anything is
/// read, and every time the app comes back — so it can never fall behind the
/// reading or the date.
final FutureProvider<PlanStatus?> planStatusProvider =
    FutureProvider<PlanStatus?>((Ref ref) async {
  final ReadingPlan plan = ref.watch(
    userPreferencesProvider.select((UserPreferences prefs) => prefs.plan),
  );
  if (!plan.isPaced) return null;

  final TodayState today = await ref.watch(todayControllerProvider.future);
  final QuranEdition? edition = today.edition;
  if (edition == null) return null;

  final ProgressRepository progressRepository =
      ref.read(progressRepositoryProvider);
  final String scope = ReadingTrack.plan.scopeFor(edition.scope);
  final int total = edition.totalAyah;
  final DateTime now = ref.read(clockProvider)();

  final ReadingProgress progress =
      await progressRepository.progressFor(scope, total);
  final DateTime dayStart =
      const ReminderSchedule(PlanScheduler.calendarDays).currentPeriodStart(now);
  final int readToday =
      await progressRepository.readCountSince(scope, dayStart);

  final int? next = await progressRepository.firstUnreadOrdinal(scope, total);
  final Ayah? nextAyah = next == null
      ? null
      : await ref.read(quranRepositoryProvider).ayahAt(edition.id, next);

  return PlanStatus(
    plan: plan,
    edition: edition,
    progress: progress,
    goal: PlanScheduler.resolve(
      plan: plan,
      progress: progress,
      notificationPreferences: PlanScheduler.calendarDays,
      readThisPeriod: readToday,
      now: now,
    ),
    today: DateTime(now.year, now.month, now.day),
    nextAyah: nextAyah,
  );
});

/// Gives a plan saved before plans had their own track the progress it was
/// measured against.
///
/// Such a plan was read on the Daily Ayah's track. Copying that reading onto
/// the plan's track once means the upgrade leaves the plan exactly where it
/// was — neither set back to the first ayah nor suddenly "behind" — while the
/// Daily Ayah keeps its own copy. A plan track that already holds reading is
/// never overwritten.
///
/// Never throws: a plan that cannot be carried over simply starts fresh.
Future<void> carryOverLegacyPlan(Ref ref) async {
  final UserPreferences preferences = ref.read(userPreferencesProvider);
  if (!preferences.plan.needsTrackSeed) return;

  try {
    final String? editionId = preferences.currentEditionId;
    final QuranEdition? edition = editionId == null
        ? null
        : await ref.read(quranRepositoryProvider).edition(editionId);
    if (edition != null) {
      final ProgressRepository progress = ref.read(progressRepositoryProvider);
      final String planScope = ReadingTrack.plan.scopeFor(edition.scope);
      final ReadingProgress existing =
          await progress.progressFor(planScope, edition.totalAyah);
      if (!existing.hasStarted && existing.totalRead == 0) {
        await progress.copyScope(edition.scope, planScope);
      }
    }
  } on Object {
    // Falls through to clearing the marker: retrying a failed copy on every
    // launch would only fail again.
  }

  try {
    await ref.read(userPreferencesProvider.notifier).update(
          preferences.copyWith(
            plan: preferences.plan.copyWith(needsTrackSeed: false),
          ),
        );
  } on Object catch (error) {
    // This runs before the app is allowed past its splash screen, so it must
    // never throw; the carry-over is simply tried again next launch.
    debugPrint('Daily Quran: could not record the plan carry-over ($error)');
  }
}
