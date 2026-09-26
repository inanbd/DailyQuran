import 'package:daily_quran/domain/entities/notification_preferences.dart';
import 'package:daily_quran/domain/entities/reading_plan.dart';
import 'package:daily_quran/domain/entities/reading_progress.dart';
import 'package:daily_quran/domain/entities/reminder_message.dart';
import 'package:daily_quran/domain/services/plan_reminder_composer.dart';
import 'package:flutter_test/flutter_test.dart';

/// A plan's own reminders: one a day, each announcing the goal as it will
/// stand that day.
void main() {
  final DateTime start = DateTime(2026, 1, 1);

  /// 100 ayat, 1–31 January: four a day.
  final ReadingPlan month = ReadingPlan(
    kind: ReadingPlanKind.custom,
    startedOn: start,
    targetDate: DateTime(2026, 1, 31),
  );

  ReadingProgress read(int count, {int total = 100}) => ReadingProgress(
        scope: 'quran#plan',
        currentOrdinal: count + 1,
        totalRead: count,
        totalAyah: total,
        startedAt: start,
        lastReadAt: start,
      );

  List<PlanReminder> compose({
    ReadingPlan? plan,
    ReadingProgress? progress,
    int readToday = 0,
    DateTime? now,
    int days = 5,
  }) {
    return PlanReminderComposer.compose(
      plan: plan ?? month,
      progress: progress ?? read(0),
      readToday: readToday,
      now: now ?? DateTime(2026, 1, 1, 6, 0),
      days: days,
    );
  }

  test('arrives once a day at the chosen time, today included', () {
    final List<PlanReminder> reminders = compose();

    expect(
      reminders.map((PlanReminder it) => it.at),
      <DateTime>[
        DateTime(2026, 1, 1, 7, 0),
        DateTime(2026, 1, 2, 7, 0),
        DateTime(2026, 1, 3, 7, 0),
        DateTime(2026, 1, 4, 7, 0),
        DateTime(2026, 1, 5, 7, 0),
      ],
    );
    expect(reminders.first.message.title, 'Today’s Qur’an goal');
    expect(
      reminders.first.message.body,
      '4 ayat to read today. Tap to begin.',
    );
  });

  test('starts tomorrow once today’s time has passed', () {
    final List<PlanReminder> reminders =
        compose(now: DateTime(2026, 1, 1, 9, 0));

    expect(reminders.first.at, DateTime(2026, 1, 2, 7, 0));
  });

  test('uses the reader’s own time', () {
    final List<PlanReminder> reminders = compose(
      plan: month.copyWith(reminderTime: const TimeOfDayValue(20, 30)),
      now: DateTime(2026, 1, 1, 9, 0),
    );

    expect(reminders.first.at, DateTime(2026, 1, 1, 20, 30));
  });

  test('announces a bigger goal on each day nothing is read', () {
    // Nothing read by the 11th: 100 left over the 21 days to the 31st.
    final List<PlanReminder> reminders =
        compose(now: DateTime(2026, 1, 11, 6, 0), days: 2);

    expect(reminders[0].message.body, '5 ayat to read today. Tap to begin.');
    expect(reminders[1].message.body, '5 ayat to read today. Tap to begin.');
  });

  test('counts down what is left of a goal already started', () {
    final List<PlanReminder> reminders = compose(
      progress: read(1),
      readToday: 1,
      now: DateTime(2026, 1, 1, 6, 0),
    );

    expect(reminders.first.at, DateTime(2026, 1, 1, 7, 0));
    expect(reminders.first.message.body, '3 ayat left of today’s goal.');
  });

  test('skips today once its goal is met', () {
    final List<PlanReminder> reminders = compose(
      progress: read(4),
      readToday: 4,
      now: DateTime(2026, 1, 1, 6, 0),
    );

    // No nagging a reader who has done the day's reading.
    expect(reminders.first.at, DateTime(2026, 1, 2, 7, 0));
  });

  test('says "ayah" for a goal of one', () {
    final List<PlanReminder> reminders = compose(
      plan: month.copyWith(targetDate: DateTime(2026, 12, 31)),
    );

    expect(reminders.first.message.body, '1 ayah to read today. Tap to begin.');
  });

  test('arms nothing with the reminder off', () {
    expect(compose(plan: month.copyWith(reminderEnabled: false)), isEmpty);
  });

  test('arms nothing without a plan', () {
    expect(compose(plan: ReadingPlan.defaults), isEmpty);
  });

  test('arms nothing once the Qur’an is finished', () {
    expect(compose(progress: read(100)), isEmpty);
  });
}
