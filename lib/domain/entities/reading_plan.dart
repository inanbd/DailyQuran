import 'package:meta/meta.dart';

import 'notification_preferences.dart';

/// The pace a reader has chosen to work through the Qur'an at.
///
/// Two shapes, deliberately: a plan either sets a *rate* and lets the finish
/// date fall where it may, or commits to a *date* and lets the rate follow
/// from it. The dated plans differ only in where the date comes from — a
/// month out, a year out, or wherever the reader chose to put it.
enum ReadingPlanKind {
  /// One ayah per reading period, with no end date.
  ///
  /// The app's original behaviour, and still the default — an existing reader
  /// who never opens the planner notices no change at all.
  oneAyah('one_ayah'),

  /// The whole scope inside a month.
  oneMonth('one_month', durationDays: 30),

  /// The whole scope inside a year.
  oneYear('one_year', durationDays: 365),

  /// The whole scope by a date of the reader's own choosing, carried on the
  /// plan itself as [ReadingPlan.targetDate].
  custom('custom');

  const ReadingPlanKind(this.storageKey, {this.durationDays});

  final String storageKey;

  /// Days the plan allows itself beyond its first, or null when the deadline
  /// is not a property of the kind — either there is none ([oneAyah]) or the
  /// reader supplies it ([custom]).
  final int? durationDays;

  /// Whether the plan works towards a date, and therefore has a portion that
  /// grows and shrinks to keep it.
  bool get isPaced => this != ReadingPlanKind.oneAyah;

  static ReadingPlanKind fromStorage(String? value) {
    return ReadingPlanKind.values.firstWhere(
      (ReadingPlanKind kind) => kind.storageKey == value,
      orElse: () => ReadingPlanKind.oneAyah,
    );
  }
}

/// A reading plan: a pace, the day it started from, and — when the reader set
/// one themselves — the day it works towards.
///
/// The start date matters only to a paced plan, where it fixes the deadline.
/// It is re-baselined rather than enforced — a reader who falls a long way
/// behind can start the plan again from today instead of facing an impossible
/// portion, which is the humane escape hatch a deadline needs.
///
/// A paced plan is read on its own track (see `ReadingTrack.plan`), with its
/// own reminder, so it never borrows from or counts against the Daily Ayah.
@immutable
class ReadingPlan {
  const ReadingPlan({
    required this.kind,
    this.startedOn,
    this.targetDate,
    this.reminderEnabled = true,
    this.reminderTime = defaultReminderTime,
    this.needsTrackSeed = false,
  });

  /// No plan: the Daily Ayah alone. What every reader gets until they choose
  /// otherwise.
  static const ReadingPlan defaults = ReadingPlan(kind: ReadingPlanKind.oneAyah);

  /// When the plan's own reminder arrives unless the reader moves it. Early,
  /// because the reminder announces the day's goal, and a goal is most use
  /// before the day has been planned.
  static const TimeOfDayValue defaultReminderTime = TimeOfDayValue(7, 0);

  final ReadingPlanKind kind;

  /// The calendar day the plan began, which is what the deadline is measured
  /// from. Null on an unpaced plan, and on a paced one that has not been
  /// started yet — the scheduler then falls back to when reading began.
  final DateTime? startedOn;

  /// The finish date a [ReadingPlanKind.custom] plan works towards. Null on
  /// every other kind, whose date follows from the start instead.
  final DateTime? targetDate;

  /// Whether the plan sends its own daily reminder with the day's goal.
  final bool reminderEnabled;

  /// When that reminder arrives, as wall-clock time.
  final TimeOfDayValue reminderTime;

  /// Set on a plan saved before plans had a track of their own.
  ///
  /// Such a plan was read on the Daily Ayah's track, so its progress lives
  /// there. Startup copies that progress onto the plan's track once, so an
  /// upgrade never sets a plan back to its first ayah, and then clears this.
  final bool needsTrackSeed;

  /// Whether the plan has a date it can actually compute.
  ///
  /// A custom plan without its date — which only corrupt storage can produce —
  /// is treated as unpaced rather than divided by nothing.
  bool get isPaced =>
      kind.isPaced && (kind != ReadingPlanKind.custom || targetDate != null);

  /// The calendar day this plan finishes on, measured from [start], or null
  /// when it sets a rate rather than a date.
  DateTime? deadlineFrom(DateTime start) {
    switch (kind) {
      case ReadingPlanKind.oneAyah:
        return null;
      case ReadingPlanKind.oneMonth:
      case ReadingPlanKind.oneYear:
        return DateTime(start.year, start.month, start.day + kind.durationDays!);
      case ReadingPlanKind.custom:
        final DateTime? target = targetDate;
        if (target == null) return null;
        return DateTime(target.year, target.month, target.day);
    }
  }

  /// Ayat a day this plan works out to across [totalAyah], or null when it
  /// sets a rate rather than a date.
  ///
  /// The plan's *daily* view, which is how it is described to the reader.
  /// Both endpoints count, because the day a plan starts and the day it ends
  /// are each a day you can read on — which is the same total
  /// [ReminderSchedule.periodsBetween] arrives at for a daily reader. Sharing
  /// the arithmetic is the point: a screen that advertised 208 a day while the
  /// engine asked for 202 would be lying about the only number on it.
  int? nominalPerDay(int totalAyah, {required DateTime today}) {
    if (totalAyah <= 0) return null;
    final DateTime start = startedOn ?? today;
    final DateTime? deadline = deadlineFrom(start);
    if (deadline == null) return null;
    // Counted in UTC epoch days so a DST shift can never lose or invent one.
    final int days = _epochDay(deadline) - _epochDay(start) + 1;
    if (days <= 0) return totalAyah;
    return ((totalAyah + days - 1) ~/ days).clamp(1, totalAyah);
  }

  ReadingPlan copyWith({
    ReadingPlanKind? kind,
    DateTime? startedOn,
    DateTime? targetDate,
    bool? reminderEnabled,
    TimeOfDayValue? reminderTime,
    bool? needsTrackSeed,
    bool clearStartedOn = false,
    bool clearTargetDate = false,
  }) {
    return ReadingPlan(
      kind: kind ?? this.kind,
      startedOn: clearStartedOn ? null : (startedOn ?? this.startedOn),
      targetDate: clearTargetDate ? null : (targetDate ?? this.targetDate),
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderTime: reminderTime ?? this.reminderTime,
      needsTrackSeed: needsTrackSeed ?? this.needsTrackSeed,
    );
  }

  static int _epochDay(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day).millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay;

  @override
  bool operator ==(Object other) =>
      other is ReadingPlan &&
      other.kind == kind &&
      other.startedOn == startedOn &&
      other.targetDate == targetDate &&
      other.reminderEnabled == reminderEnabled &&
      other.reminderTime == reminderTime &&
      other.needsTrackSeed == needsTrackSeed;

  @override
  int get hashCode => Object.hash(
        kind,
        startedOn,
        targetDate,
        reminderEnabled,
        reminderTime,
        needsTrackSeed,
      );

  @override
  String toString() =>
      'ReadingPlan(${kind.storageKey}, from: $startedOn, until: $targetDate)';
}
