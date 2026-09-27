import 'package:meta/meta.dart';

import 'daily_goal.dart';

/// What a word of congratulation is for.
enum AchievementKind {
  /// Every [ReadingStreak.celebrateEvery] days in a row of meeting the goal.
  streak,

  /// Every tenth of the Qur'an read, on either reading.
  milestone,

  /// The day's reading time reached.
  readingTime,

  /// More time spent reading today than yesterday.
  readingLonger,
}

/// Something the reader did that deserves to be noticed, and what to say.
@immutable
class Achievement {
  const Achievement({
    required this.kind,
    required this.title,
    required this.message,
  });

  final AchievementKind kind;
  final String title;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is Achievement &&
      other.kind == kind &&
      other.title == title &&
      other.message == message;

  @override
  int get hashCode => Object.hash(kind, title, message);

  @override
  String toString() => 'Achievement($kind: $title)';
}

/// Decides when the reader has done something worth a word, and finds the
/// word.
///
/// Each check compares the reading just *before* something happened with the
/// reading just after, and speaks only when a line was crossed in between.
/// That makes every congratulation arrive once, at the moment it was earned,
/// without anything having to remember that it was already said — reading
/// time only grows through a day, so a line it crossed stays crossed.
///
/// Praise only. Nothing here ever remarks on a missed day, a shorter reading
/// or a broken streak: a reader who comes back after a gap should find the
/// door open, not a tally of what they missed.
abstract final class Encouragement {
  static Achievement streak(int days) {
    return Achievement(
      kind: AchievementKind.streak,
      title: '$days days in a row',
      message: days == ReadingStreak.celebrateEvery
          ? 'You’ve met your reading goal three days running — a beautiful '
              'start. MashaAllah.'
          : 'You’ve met your reading goal $days days running. MashaAllah — '
              'keep going.',
    );
  }

  /// The tenth of the reading crossed by going from [before] to [after] ayat
  /// read out of [total], as a percentage — 10, 20 … 90 — or null when none
  /// was.
  ///
  /// The whole reading is not among them: finishing the Qur'an has a screen
  /// of its own, and a second congratulation on top of it would only be in
  /// the way.
  static int? crossedMilestone({
    required int before,
    required int after,
    required int total,
  }) {
    if (total <= 0 || after <= before) return null;
    final int from = before * 10 ~/ total;
    final int to = after * 10 ~/ total;
    if (to <= from || to >= 10) return null;
    return to * 10;
  }

  static Achievement milestone(int percent, {required bool isPlan}) {
    return Achievement(
      kind: AchievementKind.milestone,
      title: '$percent% of the Qur’an',
      message: isPlan
          ? 'Your plan has carried you $percent% of the way through the '
              'Qur’an. MashaAllah — keep going.'
          : 'Your Daily Ayah has carried you $percent% of the way through the '
              'Qur’an, one ayah at a time. MashaAllah.',
    );
  }

  /// Whether the day's reading time of [minutes] was reached in going from
  /// [before] to [after] seconds read.
  static bool reachedReadingTime({
    required int before,
    required int after,
    required int minutes,
  }) {
    if (minutes <= 0) return false;
    final int goal = minutes * 60;
    return before < goal && after >= goal;
  }

  static Achievement readingTime(int minutes) {
    return Achievement(
      kind: AchievementKind.readingTime,
      title: 'Today’s reading time is done',
      message: 'You’ve spent ${readingTimeWords(minutes * 60)} with the '
          'Qur’an today. May Allah accept it from you.',
    );
  }

  /// Least that has to have been read yesterday for "longer than yesterday"
  /// to mean anything. A few seconds on the way past is not a reading to
  /// beat.
  static const int longerThanAtLeast = 60;

  /// Whether today's reading passed yesterday's in going from [before] to
  /// [after] seconds.
  static bool readLonger({
    required int before,
    required int after,
    required int yesterday,
  }) {
    if (yesterday < longerThanAtLeast) return false;
    return before <= yesterday && after > yesterday;
  }

  static Achievement readingLonger({
    required int today,
    required int yesterday,
  }) {
    return Achievement(
      kind: AchievementKind.readingLonger,
      title: 'Longer than yesterday',
      message: 'You’ve read for ${readingTimeWords(today)} today — more than '
          'yesterday’s ${readingTimeWords(yesterday)}. Well done.',
    );
  }

  /// A line on this week's reading time against the week before's, both in
  /// seconds: praise when it grew, and nothing worse than the plain figure
  /// when it did not.
  static String weekTrend({required int week, required int previous}) {
    final int minutes = week ~/ 60;
    final int before = previous ~/ 60;
    if (minutes < 1) return 'Your reading time will show here as you read.';
    if (before < 1) return 'A good start this week — keep it going.';
    if (minutes > before) {
      return 'Up ${readingTimeWords((minutes - before) * 60)} on the week '
          'before. MashaAllah — keep it up.';
    }
    if (minutes == before) {
      return 'The same as the week before — steady and consistent.';
    }
    return 'The week before: ${readingTimeWords(previous)}.';
  }

  /// "Under a minute", "12 min", "1 h", "1 h 5 min".
  static String readingTimeWords(int seconds) {
    final int minutes = seconds ~/ 60;
    if (minutes < 1) return 'under a minute';
    if (minutes < 60) return '$minutes min';
    final int hours = minutes ~/ 60;
    final int rest = minutes % 60;
    return rest == 0 ? '$hours h' : '$hours h $rest min';
  }
}
