import 'package:meta/meta.dart';

/// One calendar day of the reader's reading: how long they spent at it, and
/// whether they met the day's goal.
///
/// Kept apart from the record of which ayat were read. That record can be
/// cleared — a plan started over, a reading begun again — while the days the
/// reader showed up are theirs whatever became of the reading since.
@immutable
class ReadingDay {
  const ReadingDay({required this.day, this.seconds = 0, this.goalMetAt});

  /// An empty day: nothing read, no goal met.
  factory ReadingDay.empty(DateTime day) =>
      ReadingDay(day: DateTime(day.year, day.month, day.day));

  /// The calendar day, at midnight.
  final DateTime day;

  /// Time spent reading on [day], in seconds.
  final int seconds;

  /// When the day's goal was first met, or null if it has not been.
  ///
  /// Met once and kept: reading marked back as unread, or a goal changed
  /// later in the day, does not take a day back from the reader.
  final DateTime? goalMetAt;

  bool get goalMet => goalMetAt != null;

  /// Whole minutes read, rounded down — the unit the reader sets a goal in.
  int get minutes => seconds ~/ 60;

  @override
  bool operator ==(Object other) =>
      other is ReadingDay &&
      other.day == day &&
      other.seconds == seconds &&
      other.goalMetAt == goalMetAt;

  @override
  int get hashCode => Object.hash(day, seconds, goalMetAt);

  @override
  String toString() => 'ReadingDay($day, ${seconds}s, met: $goalMetAt)';
}
