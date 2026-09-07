import 'package:meta/meta.dart';

import '../entities/notification_preferences.dart';
import '../entities/reading_plan.dart';
import '../entities/reading_progress.dart';
import 'reminder_schedule.dart';

/// What one reading period asks of the reader, and how the plan is faring.
@immutable
class ReadingPortion {
  const ReadingPortion({
    required this.target,
    required this.read,
    required this.nominal,
    required this.periodsBehind,
    this.deadline,
    this.projectedCompletion,
  });

  /// Nothing left to read.
  static const ReadingPortion finished = ReadingPortion(
    target: 0,
    read: 0,
    nominal: 0,
    periodsBehind: 0,
  );

  /// Ayat this reading period asks for.
  ///
  /// Fixed for an unpaced plan; for a paced one it is recomputed each period
  /// from what is left and how long is left, which is what makes missed days
  /// roll into later ones without any backlog being written down anywhere.
  final int target;

  /// Ayat actually read in this period so far.
  final int read;

  /// The plan's steady rate — what [target] would be if the reader were exactly
  /// on schedule. Shown alongside a raised target so "18 a day" stays legible
  /// even on a day that is asking for 24.
  final int nominal;

  /// Whole reading periods the reader is behind [nominal]. Zero when on or
  /// ahead of schedule.
  final int periodsBehind;

  /// The date the plan is working towards, or null when it sets a rate instead.
  final DateTime? deadline;

  /// When the reading will finish at the current target. Null once finished.
  ///
  /// For a paced plan still inside its window this is the deadline, by
  /// construction. Past the deadline it is an honest new estimate rather than a
  /// date that has already gone.
  final DateTime? projectedCompletion;

  int get remaining => target <= 0 ? 0 : (target - read).clamp(0, target);

  bool get isComplete => target <= 0 || read >= target;

  /// 0.0–1.0 through this period's portion.
  double get fraction {
    if (target <= 0) return 1;
    return (read / target).clamp(0.0, 1.0);
  }

  /// Whether the plan is asking for more than its steady rate because time was
  /// missed. The reader is told this rather than left to notice the number grew.
  bool get isCatchingUp => nominal > 0 && target > nominal;

  /// Whether the plan is asking for less than its steady rate because the
  /// reader got ahead.
  ///
  /// The mirror of [isCatchingUp], and told for the same reason: a number that
  /// quietly drops from 202 to 188 looks like a fault unless the reading that
  /// earned it is named.
  bool get isAhead => nominal > 0 && target > 0 && target < nominal;
}

/// Turns a [ReadingPlan] into this period's portion.
///
/// The catch-up rule, in one sentence: **read what is left, divided by the
/// periods left.** Nothing tracks a backlog — missing a week leaves the same
/// ayat unread with fewer periods to read them in, so the next portion grows on
/// its own and the plan's date holds.
///
/// Two guard rails keep that from turning cruel:
///
///  * Past the deadline the plan stops demanding everything at once and falls
///    back to its original steady rate, reporting a new finish date instead.
///  * The target is computed from the state at the *start* of the period, so it
///    does not shrink as the reader works through it and can never recede.
abstract final class PlanScheduler {
  static ReadingPortion resolve({
    required ReadingPlan plan,
    required ReadingProgress progress,
    required NotificationPreferences notificationPreferences,
    required int readThisPeriod,
    required DateTime now,
  }) {
    final int total = progress.totalAyah;
    if (total <= 0) return ReadingPortion.finished;

    final int remaining = (total - progress.totalRead).clamp(0, total);
    if (remaining <= 0) return ReadingPortion.finished;

    final ReminderSchedule schedule = ReminderSchedule(notificationPreferences);

    // What was still outstanding when this period began. Dividing by this
    // rather than by what is left *now* is what stops the target receding as
    // the reader reads.
    final int outstanding = (remaining + readThisPeriod).clamp(1, total);

    final int? durationDays = plan.kind.durationDays;
    if (durationDays == null) {
      // A rate, not a date: one ayah a period, for as long as it takes.
      return ReadingPortion(
        target: 1,
        read: readThisPeriod,
        nominal: 1,
        periodsBehind: 0,
        projectedCompletion: _project(schedule, now, remaining, 1),
      );
    }

    final DateTime start = _dateOnly(plan.startedOn ?? progress.startedAt ?? now);
    final DateTime deadline =
        DateTime(start.year, start.month, start.day + durationDays);

    // The rate the plan was sold at — total spread evenly over its whole
    // window. Never less than one, so it can always be divided by.
    final int planPeriods = schedule.periodsBetween(start, deadline);
    final int nominal =
        planPeriods <= 0 ? total : _ceilDiv(total, planPeriods).clamp(1, total);

    final int periodsLeft = schedule.periodsBetween(now, deadline);

    final int target;
    if (periodsLeft <= 0) {
      // The date has passed with reading still to do. Asking for everything in
      // one sitting would be arithmetically correct and completely useless, so
      // the plan holds its original pace and tells the truth about the new
      // finish date instead.
      target = nominal;
    } else {
      target = _ceilDiv(outstanding, periodsLeft).clamp(1, total);
    }

    return ReadingPortion(
      target: target,
      read: readThisPeriod,
      nominal: nominal,
      periodsBehind: _periodsBehind(
        schedule: schedule,
        start: start,
        now: now,
        totalRead: progress.totalRead,
        total: total,
        nominal: nominal,
      ),
      deadline: deadline,
      projectedCompletion: periodsLeft > 0
          ? deadline
          : _project(schedule, now, remaining, target),
    );
  }

  /// How far behind the plan's steady rate the reader is, in whole periods.
  static int _periodsBehind({
    required ReminderSchedule schedule,
    required DateTime start,
    required DateTime now,
    required int totalRead,
    required int total,
    required int nominal,
  }) {
    if (nominal <= 0) return 0;
    // Periods that have *finished*. The one in progress is not among them: a
    // reader who chose a plan this morning has not yet failed to do it, and
    // being told they were already a day behind would be both wrong and a
    // miserable way to start.
    final int elapsed = schedule.periodsBetween(start, now) - 1;
    if (elapsed <= 0) return 0;
    final int expected = (nominal * elapsed).clamp(0, total);
    final int shortfall = expected - totalRead;
    if (shortfall <= 0) return 0;
    return _ceilDiv(shortfall, nominal);
  }

  /// A finish date at [perPeriod] ayat a period, estimated in calendar days.
  ///
  /// Deliberately approximate: this is a date months or years out, where the
  /// average period length is as much precision as the number deserves.
  static DateTime? _project(
    ReminderSchedule schedule,
    DateTime now,
    int remaining,
    int perPeriod,
  ) {
    if (remaining <= 0 || perPeriod <= 0) return null;
    final int periods = _ceilDiv(remaining, perPeriod);
    final int days = (periods * schedule.averageDaysPerPeriod).ceil();
    // Beyond a human reading lifetime the number stops meaning anything.
    if (days > 365 * 50) return null;
    return DateTime(now.year, now.month, now.day + days);
  }

  static int _ceilDiv(int a, int b) => b <= 0 ? a : (a + b - 1) ~/ b;

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
