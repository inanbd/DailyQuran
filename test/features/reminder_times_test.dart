import 'package:daily_quran/app/providers.dart';
import 'package:daily_quran/app/routes.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/entities/notification_preferences.dart';
import 'package:daily_quran/domain/entities/reading_plan.dart';
import 'package:daily_quran/domain/repositories/notification_scheduler.dart';
import 'package:daily_quran/features/today/today_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// Several reminders a day: the first brings the day's ayah, the rest nudge
/// towards it — and fall quiet once it has been read.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object> onboarded({
    List<String> laterTimes = const <String>['13:00', '21:00'],
  }) =>
      <String, Object>{
        'flutter.pref.onboarding_complete': true,
        'flutter.pref.current_edition_id': 'test_edition',
        'flutter.notify.enabled': true,
        'flutter.notify.frequency': NotificationFrequency.daily.storageKey,
        'flutter.notify.time': '08:00',
        'flutter.notify.later_times': laterTimes,
      };

  Future<void> rearm(WidgetTester tester, TestHarness harness) => harness.act(
        tester,
        () => harness.container
            .read(notificationPreferencesProvider.notifier)
            .applyToScheduler(),
      );

  testWidgets('every time of the day is armed', (WidgetTester tester) async {
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
    final TestHarness harness = await TestHarness.create(
      scheduler: scheduler,
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    expect(scheduler.scheduledPreferences.last.times, const <TimeOfDayValue>[
      TimeOfDayValue(8, 0),
      TimeOfDayValue(13, 0),
      TimeOfDayValue(21, 0),
    ]);
    // Nothing read yet today, so the nudges have something to nudge towards.
    expect(scheduler.scheduledQuietUntil.last, isNull);
  });

  testWidgets('the day’s nudges fall quiet once its ayah is read',
      (WidgetTester tester) async {
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
    final TestHarness harness = await TestHarness.create(
      scheduler: scheduler,
      initialPreferences: onboarded(),
      now: DateTime(2026, 1, 7, 9, 0),
    );
    await harness.pumpApp(tester);

    await harness.act(
      tester,
      harness.container.read(todayControllerProvider.notifier).markRead,
    );
    await rearm(tester, harness);

    // Quiet until tomorrow's first reminder, which brings the next ayah.
    expect(scheduler.scheduledQuietUntil.last, DateTime(2026, 1, 8, 8, 0));
  });

  testWidgets('three reminders still bring one ayah a day',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      initialPreferences: onboarded(),
      now: DateTime(2026, 1, 7, 9, 0),
    );
    await harness.pumpApp(tester);
    final TodayController controller =
        harness.container.read(todayControllerProvider.notifier);

    await harness.act(tester, controller.markRead);

    // Past the 13:00 and 21:00 reminders: still the ayah read this morning.
    harness.clock.advanceHours(13);
    await harness.act(tester, controller.refresh);
    expect(find.text('Translation number 1.'), findsOneWidget);

    // Past tomorrow's 8:00: the next one.
    harness.clock.advanceHours(11);
    await harness.act(tester, controller.refresh);
    expect(find.text('Translation number 2.'), findsOneWidget);
  });

  testWidgets('a single reminder needs no quiet period',
      (WidgetTester tester) async {
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
    final TestHarness harness = await TestHarness.create(
      scheduler: scheduler,
      initialPreferences: onboarded(laterTimes: const <String>[]),
    );
    await harness.pumpApp(tester);

    await harness.act(
      tester,
      harness.container.read(todayControllerProvider.notifier).markRead,
    );
    await rearm(tester, harness);

    expect(scheduler.scheduledQuietUntil.last, isNull);
  });

  testWidgets('another reminder is added, and removed, in settings',
      (WidgetTester tester) async {
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
    final TestHarness harness = await TestHarness.create(
      scheduler: scheduler,
      initialPreferences: onboarded(laterTimes: const <String>[]),
    );
    await harness.pumpApp(tester);
    await harness.goTo(tester, Routes.settingsNotifications);

    expect(find.text('Reminder time'), findsOneWidget);

    final Finder add = find.text('Add another reminder');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await harness.settle(tester);
    // The picker offers a time later in the day; accept it.
    await tester.tap(find.text('OK'));
    await harness.settle(tester);

    expect(
      harness.container.read(notificationPreferencesProvider).times,
      const <TimeOfDayValue>[TimeOfDayValue(8, 0), TimeOfDayValue(12, 0)],
    );
    expect(scheduler.scheduledPreferences.last.laterTimes, hasLength(1));
    expect(find.text('First reminder'), findsOneWidget);
    expect(find.text('Second reminder'), findsOneWidget);

    final Finder remove = find.byTooltip('Remove the 12:00 PM reminder');
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await harness.settle(tester);

    expect(
      harness.container.read(notificationPreferencesProvider).times,
      const <TimeOfDayValue>[TimeOfDayValue(8, 0)],
    );
    expect(find.text('Reminder time'), findsOneWidget);
  });

  testWidgets('removing the first reminder makes the next one the first',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);
    await harness.goTo(tester, Routes.settingsNotifications);

    final Finder remove = find.byTooltip('Remove the 8:00 AM reminder');
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await harness.settle(tester);

    final NotificationPreferences preferences =
        harness.container.read(notificationPreferencesProvider);
    // The reading day now begins at 13:00.
    expect(preferences.time, const TimeOfDayValue(13, 0));
    expect(preferences.laterTimes, const <TimeOfDayValue>[TimeOfDayValue(21, 0)]);
  });

  testWidgets('a plan’s reminder can come several times a day',
      (WidgetTester tester) async {
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
    final TestHarness harness = await TestHarness.create(
      scheduler: scheduler,
      initialPreferences: onboarded(laterTimes: const <String>[]),
      now: DateTime(2026, 1, 7, 6, 0),
    );
    await harness.pumpApp(tester);
    final TodayController controller =
        harness.container.read(todayControllerProvider.notifier);

    await harness.act(
      tester,
      () => controller.choosePlan(
        const ReadingPlan(kind: ReadingPlanKind.oneMonth),
      ),
    );
    await harness.act(
      tester,
      () => controller.setPlanReminderTimes(const <TimeOfDayValue>[
        TimeOfDayValue(19, 0),
        TimeOfDayValue(7, 0),
      ]),
    );

    final List<DateTime> firstDay = <DateTime>[
      for (final PlanReminder reminder in scheduler.lastPlanReminders)
        if (reminder.at.day == 7) reminder.at,
    ];
    expect(firstDay, <DateTime>[
      DateTime(2026, 1, 7, 7, 0),
      DateTime(2026, 1, 7, 19, 0),
    ]);
    expect(
      harness.container.read(userPreferencesProvider).plan.reminderTime,
      const TimeOfDayValue(7, 0),
    );
  });
}
