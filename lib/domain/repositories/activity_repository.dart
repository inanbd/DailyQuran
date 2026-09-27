import '../entities/reading_day.dart';

/// The reader's reading days: time spent reading, and the days they met their
/// goal.
///
/// Days are calendar days on the device's clock, stored without a time so a
/// day stays the same day whatever timezone it is later read back in.
abstract interface class ActivityRepository {
  /// Adds [seconds] of reading to [day].
  Future<void> addReadingTime(DateTime day, int seconds);

  /// Records that [day]'s goal was met at [at].
  ///
  /// Returns true only the first time: a day's goal is met once, and whatever
  /// follows from meeting it — a streak congratulated — follows once.
  Future<bool> markGoalMet(DateTime day, DateTime at);

  /// What was recorded for [day], or an empty day when nothing was.
  Future<ReadingDay> dayOf(DateTime day);

  /// Every day in [from]–[to] inclusive, earliest first, days with nothing
  /// recorded filled in as empty.
  Future<List<ReadingDay>> daysBetween(DateTime from, DateTime to);

  /// Every day whose goal was met, most recent first.
  Future<List<DateTime>> goalMetDays();
}
