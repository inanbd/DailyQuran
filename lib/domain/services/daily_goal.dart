import 'package:meta/meta.dart';

/// What a day asks of the reader, for the purpose of their streak.
///
/// A day counts when the reader meets the goal they set themselves:
///
///  * a **reading time** — so many minutes with the Qur'an, or
///  * **their plan's goal** for the day.
///
/// With both, meeting either is enough: they are two ways of saying "I read
/// today", and a reader who finishes a long plan portion in less time than
/// they meant to spend has not failed at anything.
///
/// With neither, the goal is the one the app has always set: the day's Daily
/// Ayah. A bigger goal, once chosen, replaces it — reading one ayah on a day
/// that asks for two hundred is not meeting the day.
@immutable
class DailyGoal {
  const DailyGoal({required this.minutes, required this.hasPlan});

  /// The reading time asked for, in minutes, or 0 for none.
  final int minutes;

  /// Whether a plan with reading still to do sets a goal for the day.
  final bool hasPlan;

  bool get hasTimeGoal => minutes > 0;

  /// Whether the Daily Ayah is the day's goal, for want of any other.
  bool get isDailyAyah => !hasTimeGoal && !hasPlan;

  bool isMet({
    required int secondsRead,
    required bool planGoalDone,
    required int dailyAyatRead,
  }) {
    if (hasTimeGoal && secondsRead >= minutes * 60) return true;
    if (hasPlan && planGoalDone) return true;
    return isDailyAyah && dailyAyatRead > 0;
  }

  @override
  bool operator ==(Object other) =>
      other is DailyGoal && other.minutes == minutes && other.hasPlan == hasPlan;

  @override
  int get hashCode => Object.hash(minutes, hasPlan);
}

/// Runs of days on which the reader met their goal.
abstract final class ReadingStreak {
  /// A streak is congratulated at every multiple of this many days.
  static const int celebrateEvery = 3;

  /// Consecutive days the goal was met, ending today — or ending yesterday,
  /// because a day whose goal is not met *yet* has not broken anything.
  static int current(
    Iterable<DateTime> goalMetDays, {
    required DateTime today,
  }) {
    final Set<int> days = <int>{
      for (final DateTime day in goalMetDays) _epochDay(day),
    };
    int cursor = _epochDay(today);
    if (!days.contains(cursor)) cursor--;
    int length = 0;
    while (days.contains(cursor)) {
      length++;
      cursor--;
    }
    return length;
  }

  /// Whether reaching a streak of [days] deserves a word.
  static bool isCelebrated(int days) => days > 0 && days % celebrateEvery == 0;

  // Counted in UTC epoch days so a DST shift can never lose or invent one.
  static int _epochDay(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day).millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay;
}
