import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/entities/notification_preferences.dart';
import 'package:daily_quran/domain/entities/reading_plan.dart';
import 'package:daily_quran/domain/entities/reading_progress.dart';
import 'package:daily_quran/domain/services/plan_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// The plan arithmetic, and in particular what it does to someone who misses a
/// fortnight — which is the whole reason a deadline needs designing carefully.
void main() {
  const NotificationPreferences daily = NotificationPreferences(
    enabled: true,
    frequency: NotificationFrequency.daily,
    selectedWeekdays: <int>{1, 2, 3, 4, 5, 6, 7},
    time: TimeOfDayValue(8, 0),
  );

  // A Thursday, so the weekly case below has a predictable cadence.
  final DateTime start = DateTime(2026, 1, 1, 8, 0);

  ReadingProgress progress({required int totalRead, required int totalAyah}) {
    return ReadingProgress(
      scope: 'quran',
      currentOrdinal: totalRead + 1,
      totalRead: totalRead,
      totalAyah: totalAyah,
      startedAt: start,
      lastReadAt: start,
    );
  }

  ReadingPortion resolve({
    required ReadingPlanKind kind,
    required int totalRead,
    required DateTime now,
    int readThisPeriod = 0,
    int totalAyah = 100,
    NotificationPreferences preferences = daily,
  }) {
    return PlanScheduler.resolve(
      plan: ReadingPlan(
        kind: kind,
        startedOn: kind.isPaced ? start : null,
      ),
      progress: progress(totalRead: totalRead, totalAyah: totalAyah),
      notificationPreferences: preferences,
      readThisPeriod: readThisPeriod,
      now: now,
    );
  }

  test('the default plan asks for one ayah and has no date to keep', () {
    final ReadingPortion portion = resolve(
      kind: ReadingPlanKind.oneAyah,
      totalRead: 0,
      now: DateTime(2026, 1, 1, 9, 0),
    );

    expect(portion.target, 1);
    expect(portion.deadline, isNull);
    expect(portion.periodsBehind, 0);
    expect(portion.isCatchingUp, isFalse);
  });

  test('a paced plan spreads the whole edition over the days it has', () {
    // 100 ayat, 1–31 January inclusive: 31 reading days, so four a day.
    final ReadingPortion portion = resolve(
      kind: ReadingPlanKind.oneMonth,
      totalRead: 0,
      now: DateTime(2026, 1, 1, 9, 0),
    );

    expect(portion.target, 4);
    expect(portion.nominal, 4);
    expect(portion.deadline, DateTime(2026, 1, 31));
  });

  test('the real Qur’an works out to the rates the plans are sold at', () {
    int targetFor(ReadingPlanKind kind) => resolve(
          kind: kind,
          totalRead: 0,
          now: DateTime(2026, 1, 1, 9, 0),
          totalAyah: 6236,
        ).target;

    expect(targetFor(ReadingPlanKind.oneYear), 18);
    expect(targetFor(ReadingPlanKind.oneMonth), 202);
    expect(targetFor(ReadingPlanKind.oneAyah), 1);
  });

  test('missing ten days makes the next portion bigger and keeps the date', () {
    final ReadingPortion portion = resolve(
      kind: ReadingPlanKind.oneMonth,
      totalRead: 0,
      now: DateTime(2026, 1, 11, 9, 0),
    );

    // 100 still to read across the 21 days from the 11th to the 31st.
    expect(portion.target, 5);
    expect(portion.isCatchingUp, isTrue);
    // Ten days finished and missed. Today is in progress, not yet missed.
    expect(portion.periodsBehind, 10);
    // The date itself does not move — that is what catching up buys.
    expect(portion.deadline, DateTime(2026, 1, 31));
  });

  test('the rate a plan advertises is the one it goes on to ask for', () {
    // The plan screen describes each plan with `nominalPerDay`. If that ever
    // drifts from what the scheduler actually hands the reader, the only number
    // on that screen becomes a lie — so they are pinned together here.
    for (final ReadingPlanKind kind in <ReadingPlanKind>[
      ReadingPlanKind.oneMonth,
      ReadingPlanKind.oneYear,
    ]) {
      final ReadingPortion portion = resolve(
        kind: kind,
        totalRead: 0,
        now: DateTime(2026, 1, 1, 9, 0),
        totalAyah: 6236,
      );

      expect(
        kind.nominalPerDay(6236),
        portion.target,
        reason: '${kind.storageKey} advertises a rate it does not ask for',
      );
    }
  });

  test('a plan chosen this morning is not already behind', () {
    final ReadingPortion portion = resolve(
      kind: ReadingPlanKind.oneMonth,
      totalRead: 0,
      now: DateTime(2026, 1, 1, 9, 0),
    );

    // The day the plan starts is a day to read, not a day already failed.
    expect(portion.periodsBehind, 0);
    expect(portion.isCatchingUp, isFalse);
  });

  test('reading ahead makes the next portion smaller', () {
    final ReadingPortion portion = resolve(
      kind: ReadingPlanKind.oneMonth,
      totalRead: 80,
      now: DateTime(2026, 1, 11, 9, 0),
    );

    // 20 left across 21 days, so the plan stops asking for four.
    expect(portion.target, 1);
    expect(portion.isCatchingUp, isFalse);
    expect(portion.periodsBehind, 0);
  });

  test('a big day on the real Qur’an thins every day that follows it', () {
    // The plan is sold at 202 a day. Read 600 on the first day and the days
    // that remain must each get lighter — the surplus comes off the whole rest
    // of the plan rather than buying a single day off.
    final ReadingPortion onPace = resolve(
      kind: ReadingPlanKind.oneMonth,
      totalRead: 202,
      now: DateTime(2026, 1, 2, 9, 0),
      totalAyah: 6236,
    );
    final ReadingPortion ahead = resolve(
      kind: ReadingPlanKind.oneMonth,
      totalRead: 600,
      now: DateTime(2026, 1, 2, 9, 0),
      totalAyah: 6236,
    );

    expect(onPace.target, 202);
    expect(ahead.target, lessThan(onPace.target));
    expect(ahead.target, 188);
    expect(ahead.isAhead, isTrue);
    expect(ahead.isCatchingUp, isFalse);
    expect(ahead.periodsBehind, 0);
    // Reading ahead never moves the finishing date, it only lightens the load.
    expect(ahead.deadline, onPace.deadline);
  });

  test('reading far ahead keeps thinning the daily portion', () {
    // Nearly finished with a third of the plan still to run.
    final ReadingPortion portion = resolve(
      kind: ReadingPlanKind.oneMonth,
      totalRead: 6000,
      now: DateTime(2026, 1, 20, 9, 0),
      totalAyah: 6236,
    );

    // 236 left across the 12 days from the 20th to the 31st.
    expect(portion.target, 20);
    expect(portion.isAhead, isTrue);
    expect(portion.deadline, DateTime(2026, 1, 31));
  });

  test('a plan exactly on pace is neither ahead nor catching up', () {
    final ReadingPortion portion = resolve(
      kind: ReadingPlanKind.oneMonth,
      totalRead: 202,
      now: DateTime(2026, 1, 2, 9, 0),
      totalAyah: 6236,
    );

    expect(portion.target, portion.nominal);
    expect(portion.isAhead, isFalse);
    expect(portion.isCatchingUp, isFalse);
  });

  test('a finished reading is not reported as ahead', () {
    // `finished` carries a zero target, which must not read as "less than the
    // usual" and put a stray line of encouragement on a completed plan.
    expect(ReadingPortion.finished.isAhead, isFalse);
  });

  test('the target does not shrink as the reader works through it', () {
    final ReadingPortion fresh = resolve(
      kind: ReadingPlanKind.oneMonth,
      totalRead: 0,
      now: DateTime(2026, 1, 1, 9, 0),
    );
    final ReadingPortion partway = resolve(
      kind: ReadingPlanKind.oneMonth,
      totalRead: 3,
      readThisPeriod: 3,
      now: DateTime(2026, 1, 1, 9, 0),
    );

    // A target computed from what is left *now* would recede as it was read,
    // and the portion could never be finished.
    expect(partway.target, fresh.target);
    expect(partway.read, 3);
    expect(partway.remaining, 1);
    expect(partway.isComplete, isFalse);
  });

  test('the portion completes once it has been read through', () {
    final ReadingPortion portion = resolve(
      kind: ReadingPlanKind.oneMonth,
      totalRead: 4,
      readThisPeriod: 4,
      now: DateTime(2026, 1, 1, 9, 0),
    );

    expect(portion.isComplete, isTrue);
    expect(portion.remaining, 0);
    expect(portion.fraction, 1.0);
  });

  test('past its date the plan keeps its pace instead of demanding everything',
      () {
    final ReadingPortion portion = resolve(
      kind: ReadingPlanKind.oneMonth,
      totalRead: 40,
      now: DateTime(2026, 3, 1, 9, 0),
    );

    // 60 ayat left and the date a month gone. Asking for all 60 at once would
    // be arithmetically correct and completely useless.
    expect(portion.target, 4);
    expect(portion.target, portion.nominal);
    expect(portion.projectedCompletion, isNotNull);
    expect(
      portion.projectedCompletion!.isAfter(portion.deadline!),
      isTrue,
      reason: 'a date that has gone should be replaced by an honest one',
    );
  });

  test('a weekly reader gets a week of reading at a time', () {
    const NotificationPreferences weekly = NotificationPreferences(
      enabled: true,
      frequency: NotificationFrequency.weekly,
      selectedWeekdays: <int>{4},
      time: TimeOfDayValue(8, 0),
    );

    final ReadingPortion portion = resolve(
      kind: ReadingPlanKind.oneMonth,
      totalRead: 0,
      now: DateTime(2026, 1, 1, 9, 0),
      preferences: weekly,
    );

    // Five Thursdays fall between the 1st and the 31st, so the reading is
    // divided by those rather than by 31 days the reader never reads on.
    expect(portion.target, 20);
    expect(portion.nominal, 20);
  });

  test('a finished reading asks for nothing', () {
    final ReadingPortion portion = resolve(
      kind: ReadingPlanKind.oneMonth,
      totalRead: 100,
      now: DateTime(2026, 1, 5, 9, 0),
    );

    expect(portion.target, 0);
    expect(portion.isComplete, isTrue);
    expect(portion.projectedCompletion, isNull);
  });

  test('an empty edition is never divided by', () {
    final ReadingPortion portion = resolve(
      kind: ReadingPlanKind.oneMonth,
      totalRead: 0,
      totalAyah: 0,
      now: DateTime(2026, 1, 5, 9, 0),
    );

    expect(portion.target, 0);
    expect(portion.isComplete, isTrue);
  });
}
