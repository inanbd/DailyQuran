import 'package:meta/meta.dart';

/// The pace a reader has chosen to work through the Qur'an at.
///
/// Two shapes, deliberately: a plan either sets a *rate* and lets the finish
/// date fall where it may, or commits to a *date* and lets the rate follow from
/// it. Everything else about a plan derives from which of the two it is.
enum ReadingPlanKind {
  /// One ayah per reading period, with no end date.
  ///
  /// The app's original behaviour, and still the default — an existing reader
  /// who never opens the plan screen notices no change at all.
  oneAyah('one_ayah', null),

  /// The whole scope inside a month.
  oneMonth('one_month', 30),

  /// The whole scope inside a year.
  oneYear('one_year', 365);

  const ReadingPlanKind(this.storageKey, this.durationDays);

  final String storageKey;

  /// Days the plan allows itself, or null for a plan that sets a rate rather
  /// than a deadline.
  final int? durationDays;

  /// Whether the plan is working towards a date, and therefore has a portion
  /// that grows and shrinks to keep it.
  bool get isPaced => durationDays != null;

  /// Ayat a day this plan works out to across [totalAyah], or null when it
  /// sets a rate rather than a date.
  ///
  /// The plan's *daily* view, which is how it is described to the reader.
  /// Both endpoints count, because the day a plan starts and the day it ends
  /// are each a day you can read on — which is the same total
  /// [ReminderSchedule.periodsBetween] arrives at for a daily reader. Sharing
  /// the arithmetic is the point: a screen that advertised 208 a day while the
  /// engine asked for 202 would be lying about the only number on it.
  int? nominalPerDay(int totalAyah) {
    final int? days = durationDays;
    if (days == null || totalAyah <= 0) return null;
    return (totalAyah + days) ~/ (days + 1);
  }

  static ReadingPlanKind fromStorage(String? value) {
    return ReadingPlanKind.values.firstWhere(
      (ReadingPlanKind kind) => kind.storageKey == value,
      orElse: () => ReadingPlanKind.oneAyah,
    );
  }
}

/// A reading plan: a pace, and the day it started from.
///
/// The start date matters only to a paced plan, where it fixes the deadline.
/// It is re-baselined rather than enforced — a reader who falls a long way
/// behind can start the plan again from today instead of facing an impossible
/// portion, which is the humane escape hatch a deadline needs.
@immutable
class ReadingPlan {
  const ReadingPlan({required this.kind, this.startedOn});

  /// One ayah a period, no deadline. What every reader gets until they choose
  /// otherwise.
  static const ReadingPlan defaults = ReadingPlan(kind: ReadingPlanKind.oneAyah);

  final ReadingPlanKind kind;

  /// The calendar day the plan began, which is what the deadline is measured
  /// from. Null on an unpaced plan, and on a paced one that has not been
  /// started yet — the scheduler then falls back to when reading began.
  final DateTime? startedOn;

  bool get isPaced => kind.isPaced;

  ReadingPlan copyWith({
    ReadingPlanKind? kind,
    DateTime? startedOn,
    bool clearStartedOn = false,
  }) {
    return ReadingPlan(
      kind: kind ?? this.kind,
      startedOn: clearStartedOn ? null : (startedOn ?? this.startedOn),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReadingPlan &&
      other.kind == kind &&
      other.startedOn == startedOn;

  @override
  int get hashCode => Object.hash(kind, startedOn);

  @override
  String toString() => 'ReadingPlan(${kind.storageKey}, from: $startedOn)';
}
