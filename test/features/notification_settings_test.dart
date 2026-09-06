import 'package:daily_quran/app/providers.dart';
import 'package:daily_quran/app/routes.dart';
import 'package:daily_quran/domain/entities/ayah.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/entities/notification_preferences.dart';
import 'package:daily_quran/domain/entities/quran_edition.dart';
import 'package:daily_quran/domain/repositories/notification_scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object> onboarded({bool remindersOn = true}) => <String, Object>{
        'flutter.pref.onboarding_complete': true,
        'flutter.pref.current_edition_id': 'test_edition',
        'flutter.notify.enabled': remindersOn,
        'flutter.notify.frequency': NotificationFrequency.daily.storageKey,
        'flutter.notify.time': '08:00',
      };

  testWidgets('changing frequency cancels and re-arms the reminders',
      (WidgetTester tester) async {
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
    final TestHarness harness = await TestHarness.create(
      scheduler: scheduler,
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    final int armedAtStartup = scheduler.scheduledPreferences.length;
    expect(armedAtStartup, greaterThan(0));

    await harness.act(
      tester,
      () => harness.container
          .read(notificationPreferencesProvider.notifier)
          .update(
            harness.container.read(notificationPreferencesProvider).copyWith(
                  frequency: NotificationFrequency.weekly,
                  selectedWeekdays: <int>{3},
                ),
          ),
    );

    // Rescheduling happened again, with the new settings.
    expect(scheduler.scheduledPreferences.length, armedAtStartup + 1);
    final NotificationPreferences armed = scheduler.scheduledPreferences.last;
    expect(armed.frequency, NotificationFrequency.weekly);
    expect(armed.selectedWeekdays, <int>{3});
  });

  testWidgets('turning reminders off still re-arms (with nothing scheduled)',
      (WidgetTester tester) async {
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
    final TestHarness harness = await TestHarness.create(
      scheduler: scheduler,
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    await harness.act(
      tester,
      () => harness.container
          .read(notificationPreferencesProvider.notifier)
          .update(
            harness.container
                .read(notificationPreferencesProvider)
                .copyWith(enabled: false),
          ),
    );

    expect(scheduler.scheduledPreferences.last.enabled, isFalse);
  });

  testWidgets('reminders deep-link to the current edition and follow a change',
      (WidgetTester tester) async {
    final FakeContentSource english =
        FakeContentSource.single(id: 'english', title: 'English');
    final FakeContentSource french =
        FakeContentSource.single(id: 'french', title: 'French');
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
    final TestHarness harness = await TestHarness.create(
      contentSource: FakeContentSource(
        editions: <QuranEdition>[...english.editions, ...french.editions],
        ayatByEdition: <String, List<Ayah>>{
          ...english.ayatByEdition,
          ...french.ayatByEdition,
        },
      ),
      scheduler: scheduler,
      initialPreferences: <String, Object>{
        ...onboarded(),
        'flutter.pref.current_edition_id': 'english',
      },
    );
    await harness.pumpApp(tester);

    expect(scheduler.scheduledEditionIds.last, 'english');

    await harness.act(tester, () async {
      await harness.container
          .read(userPreferencesProvider.notifier)
          .setCurrentEdition('french');
      await harness.container
          .read(notificationPreferencesProvider.notifier)
          .applyToScheduler();
    });

    expect(scheduler.scheduledEditionIds.last, 'french');
  });

  testWidgets('a blocked permission is surfaced without breaking reading',
      (WidgetTester tester) async {
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler(
      status: NotificationPermissionStatus.denied,
    );
    final TestHarness harness = await TestHarness.create(
      scheduler: scheduler,
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    // Reading is unaffected.
    expect(find.text('Translation number 1.'), findsOneWidget);

    // The provider is lazy, so resolve it the way the settings screen does.
    final ReminderReadiness? readiness = await harness.act(
      tester,
      () => harness.container.read(reminderReadinessProvider.future),
    );
    expect(readiness?.notifications, NotificationPermissionStatus.denied);
    expect(readiness?.isBlocked, isTrue);
  });

  testWidgets('turning reminders on raises the OS notification prompt',
      (WidgetTester tester) async {
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler(
      status: NotificationPermissionStatus.denied,
    );
    final TestHarness harness = await TestHarness.create(
      scheduler: scheduler,
      initialPreferences: onboarded(remindersOn: false),
    );
    await harness.pumpApp(tester);
    await harness.goTo(tester, Routes.settingsNotifications);

    expect(scheduler.permissionRequests, 0);

    await tester.tap(find.byType(Switch));
    await harness.settle(tester);

    expect(scheduler.requested, contains(ReminderRequirement.notifications));
    // Permission is asked for before the reminders are armed, so they can be
    // armed as exact alarms rather than approximate ones.
    expect(scheduler.scheduledPreferences.last.enabled, isTrue);
  });

  testWidgets('the punctuality permissions are explained, then asked for',
      (WidgetTester tester) async {
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler(
      otherRequirements: FakeNotificationScheduler.androidUnasked,
    );
    final TestHarness harness = await TestHarness.create(
      scheduler: scheduler,
      initialPreferences: onboarded(remindersOn: false),
    );
    await harness.pumpApp(tester);
    await harness.goTo(tester, Routes.settingsNotifications);

    await tester.tap(find.byType(Switch));
    await harness.settle(tester);

    // The reader is told what the system screens are for before being sent to
    // them, and nothing has been requested yet.
    expect(find.text('Two more permissions'), findsOneWidget);
    expect(
      scheduler.requested,
      isNot(contains(ReminderRequirement.exactTiming)),
    );

    await tester.tap(find.text('Continue'));
    await harness.settle(tester);

    expect(
      scheduler.requested,
      containsAll(<ReminderRequirement>[
        ReminderRequirement.exactTiming,
        ReminderRequirement.background,
      ]),
    );
    expect((await scheduler.readiness()).isReady, isTrue);
  });

  testWidgets('declining the punctuality prompts still turns reminders on',
      (WidgetTester tester) async {
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler(
      otherRequirements: FakeNotificationScheduler.androidUnasked,
    );
    final TestHarness harness = await TestHarness.create(
      scheduler: scheduler,
      initialPreferences: onboarded(remindersOn: false),
    );
    await harness.pumpApp(tester);
    await harness.goTo(tester, Routes.settingsNotifications);

    await tester.tap(find.byType(Switch));
    await harness.settle(tester);
    await tester.tap(find.text('Not now'));
    await harness.settle(tester);

    expect(
      scheduler.requested,
      isNot(contains(ReminderRequirement.exactTiming)),
    );
    // Reminders are on regardless: declining costs punctuality, not the
    // feature.
    expect(
      harness.container.read(notificationPreferencesProvider).enabled,
      isTrue,
    );
    expect(scheduler.scheduledPreferences.last.enabled, isTrue);
    // And the fix stays on offer.
    expect(find.text('Exact timing'), findsOneWidget);
    expect(find.text('Not allowed'), findsNWidgets(2));
  });

  testWidgets('a requirement fixed later re-arms the reminders',
      (WidgetTester tester) async {
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler(
      otherRequirements: FakeNotificationScheduler.androidUnasked,
    );
    final TestHarness harness = await TestHarness.create(
      scheduler: scheduler,
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);
    await harness.goTo(tester, Routes.settingsNotifications);

    final int armedBefore = scheduler.scheduledPreferences.length;
    // The row sits below the fold on a test-sized viewport.
    await tester.ensureVisible(find.text('Exact timing'));
    await tester.pump();
    await tester.tap(find.text('Exact timing'));
    await harness.settle(tester);

    expect(scheduler.requested, contains(ReminderRequirement.exactTiming));
    // Being allowed exact alarms only changes anything once the reminders are
    // scheduled again, so the grant has to re-arm them.
    expect(scheduler.scheduledPreferences.length, armedBefore + 1);
    expect(find.text('Allowed'), findsOneWidget);
  });

  testWidgets('startup re-arms reminders so they survive a restart',
      (WidgetTester tester) async {
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
    final TestHarness harness = await TestHarness.create(
      scheduler: scheduler,
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    expect(scheduler.initialized, isTrue);
    expect(scheduler.scheduledPreferences, isNotEmpty);
    expect(
      scheduler.scheduledPreferences.last.time,
      const TimeOfDayValue(8, 0),
    );
  });

  testWidgets('a reminder tapped at launch opens that edition and marks it read',
      (WidgetTester tester) async {
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler(
      launchDeepLink: const QuranDeepLink(editionId: 'test_edition'),
    );
    final TestHarness harness = await TestHarness.create(
      scheduler: scheduler,
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);
    await harness.settle(tester);

    expect(find.text('Translation number 1.'), findsOneWidget);
    expect(find.text('1 of 10 read'), findsOneWidget);
    // The reader is looking at what they were sent, marked read on arrival.
    expect(find.widgetWithText(OutlinedButton, 'Read'), findsOneWidget);
  });
}
