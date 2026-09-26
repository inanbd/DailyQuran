import '../entities/reading_plan.dart';
import '../entities/reading_progress.dart';
import '../entities/reminder_message.dart';
import 'plan_scheduler.dart';

/// Works out the reminders a reading plan should arm: one a day at the
/// reader's chosen time, each announcing that day's goal.
///
/// Every goal is the one [PlanScheduler] will ask for that day *if nothing
/// more is read before it*. The app re-arms whenever the reader leaves it, and
/// reading happens only inside it, so by the time a reminder fires that
/// assumption is always true — which is what keeps a number armed days ahead
/// honest.
abstract final class PlanReminderComposer {
  /// How many days ahead are armed. Re-armed on every launch and every time the
  /// app is left, so this only needs to cover a reader who stays away.
  ///
  /// Kept to 30 so that, with the Daily Ayah's own window of up to 30, the
  /// total stays inside the 64 pending notifications iOS will hold.
  static const int window = 30;

  static const String title = 'Today’s Qur’an goal';

  static List<PlanReminder> compose({
    required ReadingPlan plan,
    required ReadingProgress progress,
    required int readToday,
    required DateTime now,
    int days = window,
  }) {
    if (!plan.isPaced || !plan.reminderEnabled) return const <PlanReminder>[];
    if (progress.totalAyah <= 0 || progress.isComplete) {
      return const <PlanReminder>[];
    }

    final List<PlanReminder> reminders = <PlanReminder>[];
    for (int offset = 0; offset < days; offset++) {
      final DateTime at = DateTime(
        now.year,
        now.month,
        now.day + offset,
        plan.reminderTime.hour,
        plan.reminderTime.minute,
      );
      if (!at.isAfter(now)) continue;

      final bool today = offset == 0;
      final ReadingPortion portion = PlanScheduler.resolve(
        plan: plan,
        progress: progress,
        notificationPreferences: PlanScheduler.calendarDays,
        // Only today has reading already counted against its goal.
        readThisPeriod: today ? readToday : 0,
        now: at,
      );

      // A goal already met needs no reminder: nagging someone who has done
      // the day's reading would teach them to ignore the next one.
      final int left = today ? portion.remaining : portion.target;
      if (left <= 0) continue;

      reminders.add(
        PlanReminder(
          at: at,
          message: ReminderMessage(
            title: title,
            body: today && portion.read > 0
                ? '${_ayat(left)} left of today’s goal.'
                : '${_ayat(left)} to read today. Tap to begin.',
          ),
        ),
      );
    }
    return reminders;
  }

  static String _ayat(int count) => count == 1 ? '1 ayah' : '$count ayat';
}
