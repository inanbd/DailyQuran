import 'package:daily_quran/app/providers.dart';
import 'package:daily_quran/app/routes.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/entities/reading_plan.dart';
import 'package:daily_quran/domain/entities/reading_progress.dart';
import 'package:daily_quran/domain/entities/reading_track.dart';
import 'package:daily_quran/domain/entities/user_preferences.dart';
import 'package:daily_quran/domain/repositories/notification_scheduler.dart';
import 'package:daily_quran/domain/repositories/progress_repository.dart';
import 'package:daily_quran/features/today/today_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// A reading plan on the real Today screen: what it asks for, how the reader
/// moves through it, and what it does to the reminders.
///
/// A plan reads on its own track, so every count here is the plan's reading,
/// never the Daily Ayah's.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The clock every test here starts on.
  final DateTime today = DateTime(2026, 1, 7, 9, 0);

  Map<String, Object> onboarded({
    ReadingPlanKind plan = ReadingPlanKind.oneAyah,
    ReminderContent content = ReminderContent.invitation,
  }) {
    return <String, Object>{
      'flutter.pref.onboarding_complete': true,
      'flutter.pref.current_edition_id': 'test_edition',
      'flutter.notify.enabled': true,
      'flutter.notify.frequency': NotificationFrequency.daily.storageKey,
      'flutter.notify.time': '08:00',
      'flutter.notify.content': content.storageKey,
      'flutter.plan.kind': plan.storageKey,
      'flutter.plan.started_on': DateTime(2026, 1, 7).millisecondsSinceEpoch,
    };
  }

  /// A hundred ayat, which a one-month plan divides into four a day.
  FakeContentSource hundred() =>
      FakeContentSource.single(count: 100, surahLength: 10);

  group('the default plan', () {
    testWidgets('reads one ayah a day and shows no portion to count through',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: onboarded(),
      );
      await harness.pumpApp(tester);

      // No plan: one reading, nothing to count, and nothing to switch to.
      expect(find.text('Today’s goal'), findsNothing);
      expect(find.text('My Plan'), findsNothing);
      expect(find.text('Today’s Ayah'), findsOneWidget);
      expect(find.text('0 of 100 read'), findsOneWidget);
    });

    testWidgets('holds position after the single ayah is read',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: onboarded(),
      );
      await harness.pumpApp(tester);

      await harness.tapButton(tester, 'Mark as read');

      // The original rule, unchanged: one ayah read is the whole of today.
      expect(find.text('Translation number 1.'), findsOneWidget);
      expect(find.text('1 of 100 read'), findsOneWidget);
    });
  });

  group('a paced plan', () {
    testWidgets('asks for a portion and says how much of it is left',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: onboarded(plan: ReadingPlanKind.oneMonth),
      );
      await harness.pumpApp(tester);

      expect(find.text('0 of 4 ayat'), findsOneWidget);
      // With a plan there are two readings, and the top of the page is the
      // choice between them rather than a title — the plan first.
      expect(find.text('Today’s Ayah'), findsNothing);
      expect(find.text('Today’s Reading'), findsNothing);
      expect(shownTrack(tester), ReadingTrack.plan);
      expect(
        tester.getCenter(find.text('My Plan')).dx,
        lessThan(tester.getCenter(find.text('Daily Ayah')).dx),
      );
    });

    testWidgets('marking read carries the reader through the portion',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: onboarded(plan: ReadingPlanKind.oneMonth),
      );
      await harness.pumpApp(tester);

      await harness.tapButton(tester, 'Mark as read');

      // Marking inside an unfinished portion brings the next ayah of it, rather
      // than sitting on one the reader has finished with.
      expect(find.text('Translation number 2.'), findsOneWidget);
      expect(find.text('1 of 4 ayat'), findsOneWidget);
    });

    testWidgets('stops at the end of the portion instead of running on',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: onboarded(plan: ReadingPlanKind.oneMonth),
      );
      await harness.pumpApp(tester);

      for (int i = 0; i < 4; i++) {
        await harness.tapButton(tester, 'Mark as read');
      }

      expect(find.text('Today’s goal is done'), findsOneWidget);
      expect(find.text('4 of 100 read'), findsOneWidget);
      // Held on the last ayah of the portion, not advanced into tomorrow's.
      expect(find.text('Translation number 4.'), findsOneWidget);
    });

    testWidgets('a missed fortnight makes the portion bigger, not the past read',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: onboarded(plan: ReadingPlanKind.oneMonth),
      );
      await harness.pumpApp(tester);

      expect(find.text('0 of 4 ayat'), findsOneWidget);

      // Away for a fortnight, having read nothing.
      harness.clock.advanceDays(14);
      await harness.act(
        tester,
        () => harness.container.read(todayControllerProvider.notifier).refresh(),
      );

      // 100 still to read across the 17 days left, so six a day — and the
      // fortnight's ayat are still unread, not marked off by the calendar.
      expect(find.text('0 of 6 ayat'), findsOneWidget);
      expect(find.text('0 of 100 read'), findsOneWidget);
      expect(find.text('Translation number 1.'), findsOneWidget);
      expect(find.textContaining('You missed some reading'), findsOneWidget);
    });

    testWidgets('a big day makes every day after it smaller, and says so',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: onboarded(plan: ReadingPlanKind.oneMonth),
      );
      await harness.pumpApp(tester);

      expect(find.text('0 of 4 ayat'), findsOneWidget);

      // A long sitting on the first day: 20 ayat against the 4 asked for.
      // Wrapped in `act` because this is real database I/O, which the fake
      // clock in a widget test never delivers if awaited directly.
      await harness.act(tester, () async {
        final ProgressRepository progress =
            harness.container.read(progressRepositoryProvider);
        for (int ordinal = 1; ordinal <= 20; ordinal++) {
          await progress.markRead(
            // The plan's own track.
            'quran#plan',
            '${((ordinal - 1) ~/ 10) + 1}:${((ordinal - 1) % 10) + 1}',
            ordinal,
            100,
            // Stamped on the day they were actually read. Left to default they
            // would carry a wall-clock time and count against tomorrow's
            // portion, which is the very thing under test.
            at: DateTime(2026, 1, 7, 10, 0),
          );
        }
      });

      harness.clock.advanceDays(1);
      await harness.act(
        tester,
        () => harness.container.read(todayControllerProvider.notifier).refresh(),
      );

      // 80 left across the 30 days from the 8th to the 6th of February, so the
      // plan asks for three instead of four — the surplus is spread over every
      // day that remains rather than buying a single day off.
      expect(find.text('0 of 3 ayat'), findsOneWidget);
      expect(find.text('20 of 100 read'), findsOneWidget);
      // A number that quietly dropped below the advertised rate reads as a
      // fault unless the reading that earned it is named.
      expect(find.textContaining('You read extra before'), findsOneWidget);
      expect(find.textContaining('You missed some reading'), findsNothing);
    });
  });

  group('what the reminder says', () {
    testWidgets('reveals nothing by default', (WidgetTester tester) async {
      final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        scheduler: scheduler,
        now: today,
        initialPreferences: onboarded(),
      );
      await harness.pumpApp(tester);

      expect(scheduler.lastMessage?.body, 'Your next ayah is ready.');
    });

    testWidgets('a plan brings its own reminder, with the day’s goal',
        (WidgetTester tester) async {
      final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        scheduler: scheduler,
        now: today,
        initialPreferences: onboarded(plan: ReadingPlanKind.oneMonth),
      );
      await harness.pumpApp(tester);

      // The Daily Ayah's reminder is about the Daily Ayah alone.
      expect(scheduler.lastMessage?.body, 'Your next ayah is ready.');

      // The plan's own come a day at a time, from tomorrow: at 9:00 today's
      // 7:00 reminder has already gone.
      final List<PlanReminder> plan = scheduler.lastPlanReminders;
      expect(plan, isNotEmpty);
      expect(plan.first.at, DateTime(2026, 1, 8, 7, 0));
      expect(plan.first.message.title, 'Today’s Qur’an goal');
      expect(plan.first.message.body, '4 ayat to read today. Tap to begin.');
      // Still no Qur'an text: the reader did not ask for any.
      expect(plan.first.message.body, isNot(contains('Translation')));
    });

    testWidgets('names the ayah when the reader asks it to',
        (WidgetTester tester) async {
      final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        scheduler: scheduler,
        now: today,
        initialPreferences: onboarded(content: ReminderContent.reference),
      );
      await harness.pumpApp(tester);

      expect(scheduler.lastMessage?.body, 'Surah 1 1:1');
    });

    testWidgets('carries the translation when the reader asks for that',
        (WidgetTester tester) async {
      final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        scheduler: scheduler,
        now: today,
        initialPreferences: onboarded(content: ReminderContent.translation),
      );
      await harness.pumpApp(tester);

      expect(scheduler.lastMessage?.title, 'Surah 1 1:1');
      expect(scheduler.lastMessage?.body, 'Translation number 1.');
    });

    testWidgets('re-arms with the ayah that is next, not the one just read',
        (WidgetTester tester) async {
      final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        scheduler: scheduler,
        now: today,
        initialPreferences: onboarded(content: ReminderContent.reference),
      );
      await harness.pumpApp(tester);

      await harness.tapButton(tester, 'Mark as read');
      await harness.act(
        tester,
        () => harness.container
            .read(notificationPreferencesProvider.notifier)
            .applyToScheduler(),
      );

      // A reminder still pointing at 1:1 would be inviting the reader back to
      // something they have already finished.
      expect(scheduler.lastMessage?.body, 'Surah 1 1:2');
    });
  });

  group('the planner screen', () {
    testWidgets('says what each plan will actually ask for',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: onboarded(),
      );
      await harness.pumpApp(tester);
      await harness.goTo(tester, Routes.planner);

      // The goal for the edition actually open, not an aspiration — and the
      // same number the plan will go on to ask for.
      expect(find.textContaining('About 4 ayat a day'), findsOneWidget);
      // A hundred ayat over a year rounds to one, and says so in the singular.
      expect(find.textContaining('About 1 ayah a day'), findsOneWidget);
      expect(find.text('Choose the day you want to finish.'), findsOneWidget);
    });

    testWidgets('says roughly how long each plan’s day will take',
        (WidgetTester tester) async {
      // The whole Qur'an, so a month is the real 202 a day.
      final TestHarness harness = await TestHarness.create(
        contentSource: FakeContentSource.single(count: 6236, surahLength: 100),
        now: today,
        initialPreferences: onboarded(),
      );
      await harness.pumpApp(tester);
      await harness.goTo(tester, Routes.planner);

      // Arabic and translation: about twenty seconds an ayah.
      expect(
        find.textContaining('About 202 ayat a day · around 1 h 5 min'),
        findsOneWidget,
      );
      expect(
        find.textContaining('About 18 ayat a day · around 6 min'),
        findsOneWidget,
      );
      expect(find.textContaining('about 20 seconds an ayah'), findsOneWidget);
    });

    testWidgets('times the day by what is on the reader’s screen',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: FakeContentSource.single(count: 6236, surahLength: 100),
        now: today,
        initialPreferences: <String, Object>{
          ...onboarded(),
          'flutter.pref.language_mode': LanguageMode.translation.storageKey,
        },
      );
      await harness.pumpApp(tester);
      await harness.goTo(tester, Routes.planner);

      // A translation alone reads faster than the Arabic with it.
      expect(
        find.textContaining('About 202 ayat a day · around 25 min'),
        findsOneWidget,
      );
    });

    testWidgets('choosing a plan starts it and shows today’s goal',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: onboarded(),
      );
      await harness.pumpApp(tester);
      await harness.goTo(tester, Routes.planner);

      final Finder choice = find.text('Finish in 1 month');
      await tester.ensureVisible(choice);
      await tester.pump();
      await tester.tap(choice);
      await harness.settle(tester);

      expect(
        harness.container.read(userPreferencesProvider).plan.kind,
        ReadingPlanKind.oneMonth,
      );
      // Started today, so it is on track, and the way in is right there.
      expect(find.text('You are on track.'), findsOneWidget);
      expect(find.text('Continue reading'), findsOneWidget);
      expect(find.text('Plan again from today'), findsOneWidget);
    });

    testWidgets('a chosen date becomes the plan and its deadline',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: onboarded(),
      );
      await harness.pumpApp(tester);
      await harness.goTo(tester, Routes.planner);

      final Finder choice = find.text('Pick a finish date');
      await tester.ensureVisible(choice);
      await tester.pump();
      await tester.tap(choice);
      await harness.settle(tester);

      // The calendar opens a month out by default; accepting it as offered.
      await harness.tapButton(tester, 'Set the date');

      final ReadingPlan plan =
          harness.container.read(userPreferencesProvider).plan;
      expect(plan.kind, ReadingPlanKind.custom);
      expect(plan.targetDate, DateTime(2026, 2, 6));
      // 100 ayat across Jan 7 – Feb 6 inclusive: 31 days, four a day — the
      // same arithmetic every dated plan runs on.
      // A month from today falls on the same day, so both plans say it.
      expect(
        find.text('Finish by Feb 6, 2026\nAbout 4 ayat a day · around 1 min'),
        findsNWidgets(2),
      );
      // And the plan's own finish date, without a year it shares with today.
      expect(find.text('Feb 6'), findsOneWidget);
    });

    testWidgets('continue reading opens the plan’s reading',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: <String, Object>{
          ...onboarded(plan: ReadingPlanKind.oneMonth),
          // Last seen on the Daily Ayah.
          'flutter.pref.reading_track': 'daily',
        },
      );
      await harness.pumpApp(tester);
      expect(shownTrack(tester), ReadingTrack.daily);

      await harness.goTo(tester, Routes.planner);
      await harness.tapButton(tester, 'Continue reading');

      expect(shownTrack(tester), ReadingTrack.plan);
      expect(find.text('0 of 4 ayat'), findsOneWidget);
    });

    testWidgets('starting over clears the plan’s reading, not the Daily Ayah’s',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: onboarded(plan: ReadingPlanKind.oneMonth),
      );
      await harness.pumpApp(tester);

      // A day of the plan, and the Daily Ayah read too.
      for (int i = 0; i < 4; i++) {
        await harness.tapButton(tester, 'Mark as read');
      }
      await harness.act(
        tester,
        () => harness.container
            .read(todayControllerProvider.notifier)
            .markReadFromNotification(),
      );
      harness.clock.advanceDays(10);
      await harness.act(
        tester,
        () => harness.container.read(todayControllerProvider.notifier).refresh(),
      );

      await harness.goTo(tester, Routes.planner);
      await harness.tapButton(tester, 'Start from the first ayah');
      // Starting over destroys read state, so it asks first.
      expect(find.text('Start from the first ayah?'), findsOneWidget);
      await harness.tapButton(tester, 'Start over');

      final ProgressRepository progress =
          harness.container.read(progressRepositoryProvider);
      final ReadingProgress? plan = await tester
          .runAsync(() => progress.progressFor('quran#plan', 100));
      final ReadingProgress? daily =
          await tester.runAsync(() => progress.progressFor('quran', 100));
      expect(plan!.totalRead, 0);
      expect(daily!.totalRead, 1);

      // Measured from today: a full month ahead, so it is on track again.
      expect(find.text('You are on track.'), findsOneWidget);
      expect(
        harness.container.read(userPreferencesProvider).plan.startedOn,
        harness.clock.now,
      );
    });

    testWidgets('stopping the plan turns it off and keeps the Daily Ayah',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: onboarded(plan: ReadingPlanKind.oneMonth),
      );
      await harness.pumpApp(tester);
      await harness.tapButton(tester, 'Mark as read');

      await harness.goTo(tester, Routes.planner);
      await harness.tapButton(tester, 'Stop my plan');
      expect(find.text('Stop your plan?'), findsOneWidget);
      await harness.tapButton(tester, 'Stop plan');

      expect(
        harness.container.read(userPreferencesProvider).plan.isPaced,
        isFalse,
      );
      // Back to choosing, with nothing of the old plan left over.
      expect(find.text('Choose the day you want to finish.'), findsOneWidget);
      final ReadingProgress? plan = await tester.runAsync(
        () => harness.container
            .read(progressRepositoryProvider)
            .progressFor('quran#plan', 100),
      );
      expect(plan!.totalRead, 0);
    });
  });

  group('choosing a plan', () {
    testWidgets('takes effect on the reading and on the reminder',
        (WidgetTester tester) async {
      final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        scheduler: scheduler,
        now: today,
        initialPreferences: onboarded(),
      );
      await harness.pumpApp(tester);

      expect(find.textContaining('of 4 ayat'), findsNothing);

      await harness.act(tester, () async {
        final UserPreferences preferences =
            harness.container.read(userPreferencesProvider);
        await harness.container.read(userPreferencesProvider.notifier).update(
              preferences.copyWith(
                plan: ReadingPlan(
                  kind: ReadingPlanKind.oneMonth,
                  startedOn: harness.clock.now,
                ),
              ),
            );
        await harness.container
            .read(notificationPreferencesProvider.notifier)
            .applyToScheduler();
      });

      expect(find.text('0 of 4 ayat'), findsOneWidget);
      expect(
        scheduler.lastPlanReminders.first.message.body,
        '4 ayat to read today. Tap to begin.',
      );
    });

    testWidgets('survives a restart of the app', (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: onboarded(plan: ReadingPlanKind.oneYear),
      );
      await harness.pumpApp(tester);

      // 100 ayat over a year is well under one a day, so the plan asks for the
      // minimum rather than rounding down to nothing.
      expect(
        harness.container.read(userPreferencesProvider).plan.kind,
        ReadingPlanKind.oneYear,
      );
      expect(find.text('0 of 1 ayah'), findsOneWidget);
    });
  });
}
