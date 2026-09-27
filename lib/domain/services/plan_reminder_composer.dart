import '../entities/notification_preferences.dart';
import '../entities/reading_plan.dart';
import '../entities/reading_progress.dart';
import '../entities/reminder_message.dart';
import 'plan_scheduler.dart';

/// Works out the reminders a reading plan should arm: one at each of the
/// reader's chosen times every day, each announcing that day's goal.
///
/// Every goal is the one [PlanScheduler] will ask for that day *if nothing
/// more is read before it*. The app re-arms whenever the reader leaves it, and
/// reading happens only inside it, so by the time a reminder fires that
/// assumption is always true — which is what keeps a number armed days ahead
/// honest.
abstract final class PlanReminderComposer {
  /// How many reminders are armed ahead. Re-armed on every launch and every
  /// time the app is left, so this only needs to cover a reader who stays
  /// away: four weeks at one reminder a day, fewer days at more.
  ///
  /// Kept to 28 so that, with the most the Daily Ayah can hold — five times
  /// on each of seven selected days — the total stays inside the 64 pending
  /// notifications iOS will hold.
  static const int window = 28;

  /// How many days ahead to look for them, today included.
  static const int horizonDays = 31;

  static const String title = 'Today’s Qur’an goal';

  static List<PlanReminder> compose({
    required ReadingPlan plan,
    required ReadingProgress progress,
    required int readToday,
    required DateTime now,
    int days = horizonDays,
    int limit = window,
  }) {
    if (!plan.isPaced || !plan.reminderEnabled) return const <PlanReminder>[];
    if (progress.totalAyah <= 0 || progress.isComplete) {
      return const <PlanReminder>[];
    }

    final List<TimeOfDayValue> times = plan.reminderTimes;
    final List<PlanReminder> reminders = <PlanReminder>[];
    for (int offset = 0; offset < days; offset++) {
      final bool today = offset == 0;
      final ReadingPortion portion = PlanScheduler.resolve(
        plan: plan,
        progress: progress,
        notificationPreferences: PlanScheduler.calendarDays,
        // Only today has reading already counted against its goal.
        readThisPeriod: today ? readToday : 0,
        now: DateTime(now.year, now.month, now.day + offset, 12),
      );

      // A goal already met needs no reminder: nagging someone who has done
      // the day's reading would teach them to ignore the next one.
      final int left = today ? portion.remaining : portion.target;
      if (left <= 0) continue;

      for (int slot = 0; slot < times.length; slot++) {
        final DateTime at = DateTime(
          now.year,
          now.month,
          now.day + offset,
          times[slot].hour,
          times[slot].minute,
        );
        if (!at.isAfter(now)) continue;

        reminders.add(
          PlanReminder(
            at: at,
            message: ReminderMessage(
              title: title,
              body: _body(
                left: left,
                started: today && portion.read > 0,
                first: slot == 0,
              ),
            ),
          ),
        );
        if (reminders.length >= limit) return reminders;
      }
    }
    return reminders;
  }

  /// The goal as it stands when the reminder arrives: begun, not yet begun,
  /// or — for a later reminder on a day nothing has been read — still there.
  static String _body({
    required int left,
    required bool started,
    required bool first,
  }) {
    if (started) return '${_ayat(left)} left of today’s goal.';
    if (first) return '${_ayat(left)} to read today. Tap to begin.';
    return '${_ayat(left)} still to read today. There’s time yet.';
  }

  static String _ayat(int count) => count == 1 ? '1 ayah' : '$count ayat';
}
