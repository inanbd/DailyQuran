import 'package:daily_quran/app/providers.dart';
import 'package:daily_quran/app/routes.dart';
import 'package:daily_quran/domain/entities/reading_day.dart';
import 'package:daily_quran/features/activity/reading_activity.dart';
import 'package:daily_quran/features/today/today_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// Streaks, milestones and reading time, as the reader meets them: counted
/// while they read, and congratulated once, at the moment it is earned.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object> onboarded({
    bool celebrations = true,
    int readingMinutes = 0,
  }) =>
      <String, Object>{
        'flutter.pref.onboarding_complete': true,
        'flutter.pref.current_edition_id': 'test_edition',
        'flutter.pref.celebrations': celebrations,
        'flutter.pref.daily_reading_minutes': readingMinutes,
      };

  /// A hundred ayat, so a single ayah is only a hundredth of the reading and
  /// no milestone gets in the way of what a test is looking at.
  FakeContentSource hundred() => FakeContentSource.single(count: 100);

  TodayController controller(TestHarness harness) =>
      harness.container.read(todayControllerProvider.notifier);

  /// Reads the day's ayah the next morning.
  Future<void> readNextDay(WidgetTester tester, TestHarness harness) async {
    harness.clock.advanceDays(1);
    await harness.act(tester, controller(harness).refresh);
    await harness.act(tester, controller(harness).markRead);
  }

  Future<void> dismiss(WidgetTester tester, TestHarness harness) async {
    await tester.tap(find.text('Continue'));
    await harness.settle(tester);
  }

  /// A touch on the page, [seconds] after the last — a sign of reading.
  Future<void> touchAfter(
    WidgetTester tester,
    TestHarness harness,
    int seconds,
  ) async {
    harness.clock.now = harness.clock.now.add(Duration(seconds: seconds));
    await tester.tapAt(tester.getCenter(find.text('Today’s Ayah')));
    await harness.settle(tester);
  }

  /// The reader's reading as it now stands. Read on the real event loop:
  /// it is database I/O, which the widget test's fake clock never finishes.
  Future<ReadingSummary> summary(
    WidgetTester tester,
    TestHarness harness,
  ) async =>
      (await tester.runAsync(
        () => harness.container.read(readingSummaryProvider.future),
      ))!;

  Future<ReadingDay> today(WidgetTester tester, TestHarness harness) async =>
      (await summary(tester, harness)).today;

  group('the streak', () {
    testWidgets('three days running of the Daily Ayah is congratulated',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        initialPreferences: onboarded(),
      );
      await harness.pumpApp(tester);

      await harness.act(tester, controller(harness).markRead);
      expect(find.text('Continue'), findsNothing);

      await readNextDay(tester, harness);
      expect(find.text('Continue'), findsNothing);

      await readNextDay(tester, harness);
      expect(find.text('3 days in a row'), findsOneWidget);

      await dismiss(tester, harness);
      expect(find.text('3 days in a row'), findsNothing);

      // A fourth day is noted but not remarked on; the sixth would be.
      await readNextDay(tester, harness);
      expect(find.text('Continue'), findsNothing);
      expect(
        (await summary(tester, harness)).streak,
        4,
      );
    });

    testWidgets('a missed day starts it again, without a word about it',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        initialPreferences: onboarded(),
      );
      await harness.pumpApp(tester);

      await harness.act(tester, controller(harness).markRead);
      await readNextDay(tester, harness);
      harness.clock.advanceDays(1); // a day missed
      await readNextDay(tester, harness);

      expect(find.text('Continue'), findsNothing);
      expect(
        (await summary(tester, harness)).streak,
        1,
      );
    });

    testWidgets('a day with a reading time set asks for that time',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        initialPreferences: onboarded(readingMinutes: 10),
      );
      await harness.pumpApp(tester);

      await harness.act(tester, controller(harness).markRead);

      // Reading the Daily Ayah alone no longer meets the day.
      expect((await today(tester, harness)).goalMet, isFalse);
    });
  });

  group('milestones', () {
    testWidgets('a tenth of the Qur’an is congratulated once',
        (WidgetTester tester) async {
      // Ten ayat: the first one read is a tenth of the reading.
      final TestHarness harness = await TestHarness.create(
        initialPreferences: onboarded(),
      );
      await harness.pumpApp(tester);

      await harness.act(tester, controller(harness).markRead);
      expect(find.text('10% of the Qur’an'), findsOneWidget);
      await dismiss(tester, harness);

      // Marked unread and read again is not a new achievement.
      await harness.act(tester, controller(harness).markUnread);
      await harness.act(tester, controller(harness).markRead);
      expect(find.text('10% of the Qur’an'), findsNothing);
    });

    testWidgets('with celebrations off, nothing is said but all is kept',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        initialPreferences: onboarded(celebrations: false),
      );
      await harness.pumpApp(tester);

      await harness.act(tester, controller(harness).markRead);

      expect(find.text('10% of the Qur’an'), findsNothing);
      expect((await today(tester, harness)).goalMet, isTrue);
      final bool reachedAgain = (await tester.runAsync(
        () => harness.container
            .read(progressRepositoryProvider)
            .reachMilestone('quran', 10, harness.clock.now),
      ))!;
      expect(reachedAgain, isFalse, reason: 'the milestone was recorded');
    });
  });

  group('reading time', () {
    testWidgets('is counted while the reader reads, and reaching it is marked',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        initialPreferences: onboarded(readingMinutes: 5),
      );
      await harness.pumpApp(tester);

      expect(find.text('Reading time · 0 of 5 min today'), findsOneWidget);

      // Two minutes of reading, a touch every thirty seconds.
      for (int i = 0; i < 4; i++) {
        await touchAfter(tester, harness, 30);
      }
      expect((await today(tester, harness)).seconds, 120);
      expect(find.text('Reading time · 2 of 5 min today'), findsOneWidget);

      // Three more minutes reaches the goal.
      for (int i = 0; i < 6; i++) {
        await touchAfter(tester, harness, 30);
      }
      expect((await today(tester, harness)).seconds, 300);
      expect(find.text('Today’s reading time is done'), findsWidgets);
      expect(find.textContaining('5 min with the Qur’an'), findsOneWidget);
      expect((await today(tester, harness)).goalMet, isTrue);
    });

    testWidgets('time with nobody reading is not counted',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        initialPreferences: onboarded(readingMinutes: 30),
      );
      await harness.pumpApp(tester);

      await touchAfter(tester, harness, 10);
      // The phone left open on the page for an hour.
      await touchAfter(tester, harness, 3600);

      // Ten seconds read, and two minutes' grace after them — not the hour.
      expect((await today(tester, harness)).seconds, 130);
    });

    testWidgets('stops counting when the reader leaves the Today tab',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        initialPreferences: onboarded(readingMinutes: 30),
      );
      await harness.pumpApp(tester);

      harness.clock.now = harness.clock.now.add(const Duration(seconds: 45));
      await harness.goTo(tester, Routes.settings);
      expect((await today(tester, harness)).seconds, 45);

      // A minute in settings, then straight back and away again: the minute
      // was not reading, and neither was the moment passing through.
      harness.clock.now = harness.clock.now.add(const Duration(minutes: 1));
      await harness.goTo(tester, Routes.today);
      await harness.goTo(tester, Routes.settings);
      expect((await today(tester, harness)).seconds, 45);
    });

    testWidgets('reading longer than yesterday is praised',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        initialPreferences: onboarded(),
      );
      await harness.pumpApp(tester);

      // Yesterday: a minute and a half, then away from the page.
      for (int i = 0; i < 3; i++) {
        await touchAfter(tester, harness, 30);
      }
      await harness.goTo(tester, Routes.settings);

      // Today: back to it.
      harness.clock.advanceDays(1);
      await harness.goTo(tester, Routes.today);
      await harness.act(tester, controller(harness).refresh);

      // Level with yesterday is not longer than it.
      for (int i = 0; i < 3; i++) {
        await touchAfter(tester, harness, 30);
      }
      expect((await today(tester, harness)).seconds, 90);
      expect(find.text('Longer than yesterday'), findsNothing);

      await touchAfter(tester, harness, 30);
      expect(find.text('Longer than yesterday'), findsOneWidget);
    });
  });

  group('the Progress tab', () {
    testWidgets('shows the streak, the time read and what counts',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        initialPreferences: onboarded(celebrations: false),
      );
      await harness.pumpApp(tester);

      await harness.act(tester, controller(harness).markRead);
      await harness.goTo(tester, Routes.progress);

      expect(find.text('YOUR READING'), findsOneWidget);
      expect(find.text('day in a row'), findsOneWidget);
      expect(
        find.text('A day counts towards your streak when you read your '
            'Daily Ayah.'),
        findsOneWidget,
      );
      expect(find.text('Set a daily reading time'), findsOneWidget);
    });

    testWidgets('names the reading time once one is set',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        initialPreferences: onboarded(readingMinutes: 15),
      );
      await harness.pumpApp(tester);
      await harness.goTo(tester, Routes.progress);

      expect(
        find.text('A day counts towards your streak when you read for '
            '15 min.'),
        findsOneWidget,
      );
      expect(find.text('Today · 0 of 15 min'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('a daily reading time is chosen under Reading',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        initialPreferences: onboarded(),
      );
      await harness.pumpApp(tester);
      await harness.goTo(tester, Routes.settingsReading);

      final Finder ten = find.text('10 min a day');
      await tester.ensureVisible(ten);
      await tester.tap(ten);
      await harness.settle(tester);

      expect(
        harness.container.read(userPreferencesProvider).dailyReadingMinutes,
        10,
      );

      await harness.goTo(tester, Routes.settings);
      expect(find.text('10 min a day'), findsOneWidget);
    });
  });
}
