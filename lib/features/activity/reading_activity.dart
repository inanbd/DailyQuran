import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/reading_day.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/entities/reading_track.dart';
import '../../domain/entities/user_preferences.dart';
import '../../domain/repositories/activity_repository.dart';
import '../../domain/repositories/progress_repository.dart';
import '../../domain/services/daily_goal.dart';
import '../../domain/services/encouragement.dart';
import '../../domain/services/plan_scheduler.dart';
import '../../domain/services/reading_session.dart';

/// Words of congratulation waiting to be shown, oldest first.
///
/// Filled by [ReadingActivity] and emptied by whatever shows them — the app
/// root, which puts them in front of the reader wherever they are.
class CelebrationQueue extends Notifier<List<Achievement>> {
  @override
  List<Achievement> build() => const <Achievement>[];

  void add(List<Achievement> achievements) {
    if (achievements.isEmpty) return;
    state = <Achievement>[...state, ...achievements];
  }

  /// Everything waiting, which is then no longer waiting.
  List<Achievement> takeAll() {
    final List<Achievement> all = state;
    state = const <Achievement>[];
    return all;
  }
}

final NotifierProvider<CelebrationQueue, List<Achievement>>
    celebrationsProvider =
    NotifierProvider<CelebrationQueue, List<Achievement>>(CelebrationQueue.new);

/// The reader's reading at a glance: today against their goal, their streak,
/// and the week's reading time.
@immutable
class ReadingSummary {
  const ReadingSummary({
    required this.goal,
    required this.today,
    required this.goalMetToday,
    required this.streak,
    required this.week,
    required this.previousWeekSeconds,
  });

  /// What today asks for.
  final DailyGoal goal;

  final ReadingDay today;

  final bool goalMetToday;

  /// Days in a row the goal has been met, up to today or yesterday.
  final int streak;

  /// The last seven days, oldest first and today last.
  final List<ReadingDay> week;

  /// Time read in the seven days before [week].
  final int previousWeekSeconds;

  int get weekSeconds =>
      week.fold(0, (int total, ReadingDay day) => total + day.seconds);
}

/// Today's reading measured against the goal, before anything is recorded.
@immutable
class _TodayStanding {
  const _TodayStanding({
    required this.goal,
    required this.day,
    required this.planGoalDone,
    required this.dailyAyatRead,
  });

  final DailyGoal goal;
  final ReadingDay day;
  final bool planGoalDone;
  final int dailyAyatRead;

  bool get isMet =>
      day.goalMet ||
      goal.isMet(
        secondsRead: day.seconds,
        planGoalDone: planGoalDone,
        dailyAyatRead: dailyAyatRead,
      );
}

/// Records what the reader does — time spent reading, ayat read — and says
/// something when it adds up to something.
///
/// The one place a congratulation is decided. Every check here compares the
/// reading before an event with the reading after it (see [Encouragement]),
/// so each is said once, at the moment it was earned.
///
/// Never throws. Encouragement is a kindness on top of the reading; a failure
/// here must never cost the reader the ayah they just read.
class ReadingActivity {
  ReadingActivity(this._ref);

  final Ref _ref;

  /// Adds [stretch] to the reader's reading time.
  Future<void> recordTime(ReadingStretch stretch) async {
    final Map<DateTime, int> byDay = stretch.secondsByDay();
    if (byDay.isEmpty) return;

    try {
      final ActivityRepository days = _ref.read(activityRepositoryProvider);
      final DateTime now = _now();
      final DateTime today = _dateOnly(now);
      final int before = (await days.dayOf(today)).seconds;
      for (final MapEntry<DateTime, int> entry in byDay.entries) {
        await days.addReadingTime(entry.key, entry.value);
      }
      final int after = (await days.dayOf(today)).seconds;
      final int yesterday = (await days.dayOf(_addDays(today, -1))).seconds;
      final int minutes = _preferences.dailyReadingMinutes;

      _celebrate(<Achievement>[
        if (Encouragement.reachedReadingTime(
          before: before,
          after: after,
          minutes: minutes,
        ))
          Encouragement.readingTime(minutes),
        if (Encouragement.readLonger(
          before: before,
          after: after,
          yesterday: yesterday,
        ))
          Encouragement.readingLonger(today: after, yesterday: yesterday),
        ...await _recordGoal(now),
      ]);
    } on Object catch (error) {
      debugPrint('Daily Quran: reading time not recorded ($error)');
    }
    _ref.invalidate(readingSummaryProvider);
  }

  /// Notices an ayah just marked read on [track], taking its reading of
  /// [edition] from [before] to [after].
  Future<void> ayahRead({
    required QuranEdition edition,
    required ReadingTrack track,
    required ReadingProgress before,
    required ReadingProgress after,
  }) async {
    try {
      final DateTime now = _now();
      final List<Achievement> achieved = <Achievement>[];

      // Placeholder text is not the Qur'an, and a tenth of it is not a tenth
      // of the Qur'an.
      final int? percent = edition.isFixture
          ? null
          : Encouragement.crossedMilestone(
              before: before.totalRead,
              after: after.totalRead,
              total: after.totalAyah,
            );
      if (percent != null &&
          await _ref
              .read(progressRepositoryProvider)
              .reachMilestone(after.scope, percent, now)) {
        achieved.add(
          Encouragement.milestone(
            percent,
            isPlan: track == ReadingTrack.plan,
          ),
        );
      }

      achieved.addAll(await _recordGoal(now));
      _celebrate(achieved);
    } on Object catch (error) {
      debugPrint('Daily Quran: reading not noticed ($error)');
    }
    _ref.invalidate(readingSummaryProvider);
  }

  /// The reader's reading at a glance, for the Progress and Today screens.
  Future<ReadingSummary> summary() async {
    final DateTime now = _now();
    final ActivityRepository days = _ref.read(activityRepositoryProvider);
    final _TodayStanding standing = await _standing(now);
    final DateTime today = standing.day.day;

    final List<DateTime> goalDays = <DateTime>[
      // A goal met but not yet recorded — a reading time lowered below what
      // was already read — is shown as met; the next thing read records it.
      if (standing.isMet) today,
      ...await days.goalMetDays(),
    ];
    final List<ReadingDay> previous =
        await days.daysBetween(_addDays(today, -13), _addDays(today, -7));

    return ReadingSummary(
      goal: standing.goal,
      today: standing.day,
      goalMetToday: standing.isMet,
      streak: ReadingStreak.current(goalDays, today: today),
      week: await days.daysBetween(_addDays(today, -6), today),
      previousWeekSeconds:
          previous.fold(0, (int total, ReadingDay day) => total + day.seconds),
    );
  }

  /// Records today's goal as met if it now is, and congratulates the streak
  /// that makes, when it is one worth a word.
  Future<List<Achievement>> _recordGoal(DateTime now) async {
    final _TodayStanding standing = await _standing(now);
    if (standing.day.goalMet || !standing.isMet) return const <Achievement>[];

    final ActivityRepository days = _ref.read(activityRepositoryProvider);
    if (!await days.markGoalMet(standing.day.day, now)) {
      return const <Achievement>[];
    }
    final int streak = ReadingStreak.current(
      await days.goalMetDays(),
      today: standing.day.day,
    );
    return ReadingStreak.isCelebrated(streak)
        ? <Achievement>[Encouragement.streak(streak)]
        : const <Achievement>[];
  }

  /// Where today stands against the reader's goal.
  Future<_TodayStanding> _standing(DateTime now) async {
    final UserPreferences preferences = _preferences;
    final DateTime today = _dateOnly(now);
    final ReadingDay day =
        await _ref.read(activityRepositoryProvider).dayOf(today);

    final QuranEdition? edition = await _edition(preferences);
    if (edition == null || edition.totalAyah <= 0) {
      return _TodayStanding(
        goal: DailyGoal(
          minutes: preferences.dailyReadingMinutes,
          hasPlan: false,
        ),
        day: day,
        planGoalDone: false,
        dailyAyatRead: 0,
      );
    }

    final ProgressRepository progress = _ref.read(progressRepositoryProvider);
    final int dailyAyatRead = await progress.readCountSince(
      ReadingTrack.daily.scopeFor(edition.scope),
      today,
    );

    bool hasPlan = false;
    bool planGoalDone = false;
    if (preferences.plan.isPaced) {
      final String scope = ReadingTrack.plan.scopeFor(edition.scope);
      final ReadingProgress plan =
          await progress.progressFor(scope, edition.totalAyah);
      final DateTime? finished = plan.completedAt;
      if (plan.isComplete) {
        // A finished plan asks nothing more of anyone — except on the day it
        // was finished, when reading its last ayah was the day's goal met.
        hasPlan = finished != null && _dateOnly(finished) == today;
        planGoalDone = hasPlan;
      } else {
        hasPlan = true;
        final int readToday = await progress.readCountSince(scope, today);
        planGoalDone = readToday > 0 &&
            PlanScheduler.resolve(
              plan: preferences.plan,
              progress: plan,
              notificationPreferences: PlanScheduler.calendarDays,
              readThisPeriod: readToday,
              now: now,
            ).isComplete;
      }
    }

    return _TodayStanding(
      goal: DailyGoal(
        minutes: preferences.dailyReadingMinutes,
        hasPlan: hasPlan,
      ),
      day: day,
      planGoalDone: planGoalDone,
      dailyAyatRead: dailyAyatRead,
    );
  }

  Future<QuranEdition?> _edition(UserPreferences preferences) async {
    final String? id = preferences.currentEditionId;
    if (id == null) return null;
    return _ref.read(quranRepositoryProvider).edition(id);
  }

  /// Queues [achieved] to be shown — unless the reader asked for quiet. The
  /// record is kept either way.
  void _celebrate(List<Achievement> achieved) {
    if (achieved.isEmpty || !_preferences.celebrations) return;
    _ref.read(celebrationsProvider.notifier).add(achieved);
  }

  UserPreferences get _preferences => _ref.read(userPreferencesProvider);

  DateTime _now() => _ref.read(clockProvider)();

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _addDays(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);
}

final Provider<ReadingActivity> readingActivityProvider =
    Provider<ReadingActivity>(ReadingActivity.new);

/// The reader's reading at a glance.
///
/// Recomputed whenever the goal it measures against changes, and invalidated
/// by [ReadingActivity] whenever it records anything.
final FutureProvider<ReadingSummary> readingSummaryProvider =
    FutureProvider<ReadingSummary>((Ref ref) {
  ref.watch(
    userPreferencesProvider.select(
      (UserPreferences prefs) => (
        prefs.dailyReadingMinutes,
        prefs.plan,
        prefs.currentEditionId,
      ),
    ),
  );
  return ref.read(readingActivityProvider).summary();
});
