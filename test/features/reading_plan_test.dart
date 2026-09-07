import 'package:daily_quran/app/providers.dart';
import 'package:daily_quran/app/routes.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/entities/reading_plan.dart';
import 'package:daily_quran/domain/entities/user_preferences.dart';
import 'package:daily_quran/domain/repositories/progress_repository.dart';
import 'package:daily_quran/features/today/today_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// A reading plan on the real Today screen: what it asks for, how the reader
/// moves through it, and what it does to the reminder.
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

      // Counting to one every day would be noise, so there is nothing to count.
      expect(find.textContaining('Today ·'), findsNothing);
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

      expect(find.text('Today · 0 of 4'), findsOneWidget);
      // "Today's Ayah" would be a misdescription of a four-ayah portion.
      expect(find.text('Today’s Reading'), findsOneWidget);
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
      expect(find.text('Today · 1 of 4'), findsOneWidget);
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

      expect(find.text('Today’s portion is done'), findsOneWidget);
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

      expect(find.text('Today · 0 of 4'), findsOneWidget);

      // Away for a fortnight, having read nothing.
      harness.clock.advanceDays(14);
      await harness.act(
        tester,
        () => harness.container.read(todayControllerProvider.notifier).refresh(),
      );

      // 100 still to read across the 17 days left, so six a day — and the
      // fortnight's ayat are still unread, not marked off by the calendar.
      expect(find.text('Today · 0 of 6'), findsOneWidget);
      expect(find.text('0 of 100 read'), findsOneWidget);
      expect(find.text('Translation number 1.'), findsOneWidget);
      expect(find.textContaining('More than the usual 4'), findsOneWidget);
    });

    testWidgets('a big day makes every day after it smaller, and says so',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: onboarded(plan: ReadingPlanKind.oneMonth),
      );
      await harness.pumpApp(tester);

      expect(find.text('Today · 0 of 4'), findsOneWidget);

      // A long sitting on the first day: 20 ayat against the 4 asked for.
      // Wrapped in `act` because this is real database I/O, which the fake
      // clock in a widget test never delivers if awaited directly.
      await harness.act(tester, () async {
        final ProgressRepository progress =
            harness.container.read(progressRepositoryProvider);
        for (int ordinal = 1; ordinal <= 20; ordinal++) {
          await progress.markRead(
            'quran',
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
      expect(find.text('Today · 0 of 3'), findsOneWidget);
      expect(find.text('20 of 100 read'), findsOneWidget);
      // A number that quietly dropped below the advertised rate reads as a
      // fault unless the reading that earned it is named.
      expect(find.textContaining('Fewer than the usual 4'), findsOneWidget);
      expect(find.textContaining('More than the usual'), findsNothing);
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

    testWidgets('counts out the portion once a plan asks for one',
        (WidgetTester tester) async {
      final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        scheduler: scheduler,
        now: today,
        initialPreferences: onboarded(plan: ReadingPlanKind.oneMonth),
      );
      await harness.pumpApp(tester);

      expect(scheduler.lastMessage?.body, 'Your 4 ayat are ready.');
      // Still no Qur'an text: the reader did not ask for any.
      expect(scheduler.lastMessage?.body, isNot(contains('Translation')));
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

  group('the plan screen', () {
    testWidgets('says what each plan will actually ask for',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: onboarded(),
      );
      await harness.pumpApp(tester);
      await harness.goTo(tester, Routes.settingsPlan);

      // The rate for the edition actually open, not an aspiration — and the
      // same number the portion below will ask for.
      expect(find.text('About 4 ayat a day.'), findsOneWidget);
      // A hundred ayat over a year rounds to one, and says so in the singular.
      expect(find.text('About 1 ayah a day.'), findsOneWidget);
      expect(find.text('The steady pace. No end date.'), findsOneWidget);
    });

    testWidgets('choosing a plan takes effect and shows the date it holds',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        now: today,
        initialPreferences: onboarded(),
      );
      await harness.pumpApp(tester);
      await harness.goTo(tester, Routes.settingsPlan);

      final Finder choice = find.text('Finish in a month');
      await tester.ensureVisible(choice);
      await tester.pump();
      await tester.tap(choice);
      await harness.settle(tester);

      expect(
        harness.container.read(userPreferencesProvider).plan.kind,
        ReadingPlanKind.oneMonth,
      );
      // Started today, so the date is a month out and it is not behind.
      expect(find.textContaining('On track for'), findsOneWidget);
      expect(find.text('Start this plan from today'), findsOneWidget);
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

      expect(find.textContaining('Today ·'), findsNothing);

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

      expect(find.text('Today · 0 of 4'), findsOneWidget);
      expect(scheduler.lastMessage?.body, 'Your 4 ayat are ready.');
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
      expect(find.textContaining('Today ·'), findsNothing);
    });
  });
}
