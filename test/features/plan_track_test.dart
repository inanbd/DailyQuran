import 'package:daily_quran/app/providers.dart';
import 'package:daily_quran/app/routes.dart';
import 'package:daily_quran/data/local/progress_dao.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/entities/reading_plan.dart';
import 'package:daily_quran/domain/entities/reading_progress.dart';
import 'package:daily_quran/domain/entities/reading_track.dart';
import 'package:daily_quran/domain/repositories/notification_scheduler.dart';
import 'package:daily_quran/domain/repositories/progress_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// The plan and the Daily Ayah as two separate readings: each keeps its own
/// place and its own progress, and each reminder leads to its own reading.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final DateTime today = DateTime(2026, 1, 7, 9, 0);

  Map<String, Object> withPlan({String? track, bool legacy = false}) {
    return <String, Object>{
      'flutter.pref.onboarding_complete': true,
      'flutter.pref.current_edition_id': 'test_edition',
      'flutter.notify.enabled': true,
      'flutter.notify.frequency': NotificationFrequency.daily.storageKey,
      'flutter.notify.time': '08:00',
      'flutter.plan.kind': ReadingPlanKind.oneMonth.storageKey,
      'flutter.plan.started_on': DateTime(2026, 1, 7).millisecondsSinceEpoch,
      if (!legacy) 'flutter.plan.track': 'separate',
      'flutter.pref.reading_track': ?track,
    };
  }

  /// A hundred ayat: a one-month plan asks for four a day.
  FakeContentSource hundred() =>
      FakeContentSource.single(count: 100, surahLength: 10);

  Future<ReadingProgress> progressOf(
    WidgetTester tester,
    TestHarness harness,
    String scope,
  ) async {
    final ProgressRepository repository =
        harness.container.read(progressRepositoryProvider);
    return (await tester.runAsync(() => repository.progressFor(scope, 100)))!;
  }

  /// Taps one side of the Daily Ayah / My Plan switch at the top of Today.
  Future<void> switchTo(
    WidgetTester tester,
    TestHarness harness,
    String label,
  ) async {
    final Finder side = find.text(label);
    await tester.ensureVisible(side);
    await tester.pump();
    await tester.tap(side);
    await harness.settle(tester);
  }

  testWidgets('the plan and the Daily Ayah keep their own reading',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: hundred(),
      now: today,
      initialPreferences: withPlan(),
    );
    await harness.pumpApp(tester);

    // A plan opens on its own reading.
    expect(shownTrack(tester), ReadingTrack.plan);
    await harness.tapButton(tester, 'Mark as read');
    await harness.tapButton(tester, 'Mark as read');
    expect(find.text('2 of 100 read'), findsOneWidget);

    // The Daily Ayah has read nothing: it starts at the beginning.
    await switchTo(tester, harness, 'Daily Ayah');
    expect(shownTrack(tester), ReadingTrack.daily);
    expect(find.text('Translation number 1.'), findsOneWidget);
    expect(find.text('0 of 100 read'), findsOneWidget);
    await harness.tapButton(tester, 'Mark as read');
    expect(find.text('1 of 100 read'), findsOneWidget);

    // And the plan carries on where it was, uncounted by the Daily Ayah.
    await switchTo(tester, harness, 'My Plan');
    expect(find.text('Translation number 3.'), findsOneWidget);
    expect(find.text('2 of 100 read'), findsOneWidget);
    expect(find.text('2 of 4 ayat'), findsOneWidget);

    expect((await progressOf(tester, harness, 'quran')).totalRead, 1);
    expect((await progressOf(tester, harness, 'quran#plan')).totalRead, 2);
  });

  testWidgets('the reading chosen last is the one that opens next time',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: hundred(),
      now: today,
      initialPreferences: withPlan(),
    );
    await harness.pumpApp(tester);
    await switchTo(tester, harness, 'Daily Ayah');

    final SharedPreferences prefs =
        harness.container.read(sharedPreferencesProvider);
    expect(prefs.getString('pref.reading_track'), 'daily');
  });

  group('a plan’s reminder', () {
    testWidgets('opens today’s goal first, and reads nothing',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        scheduler: FakeNotificationScheduler(
          launchDeepLink: const QuranDeepLink(
            editionId: 'test_edition',
            kind: ReminderKind.plan,
          ),
        ),
        now: today,
        initialPreferences: withPlan(track: 'daily'),
      );
      await harness.pumpApp(tester);

      expect(find.text('Today’s goal'), findsOneWidget);
      expect(find.text('Your Qur’an plan'), findsOneWidget);
      // The goal, how much is done, and where the reading starts.
      expect(find.text('4'), findsOneWidget);
      expect(find.text('0 read · 4 to go'), findsOneWidget);
      expect(find.text('You will start at Surah 1 · 1:1'), findsOneWidget);
      expect(find.text('You are on track.'), findsOneWidget);
      expect(find.text('Continue reading'), findsOneWidget);

      // Arriving marked nothing, in either reading.
      expect((await progressOf(tester, harness, 'quran')).totalRead, 0);
      expect((await progressOf(tester, harness, 'quran#plan')).totalRead, 0);
    });

    testWidgets('continue reading goes into the plan’s reading',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        scheduler: FakeNotificationScheduler(
          launchDeepLink: const QuranDeepLink(
            editionId: 'test_edition',
            kind: ReminderKind.plan,
          ),
        ),
        now: today,
        // Last seen on the Daily Ayah, which must not be what opens.
        initialPreferences: withPlan(track: 'daily'),
      );
      await harness.pumpApp(tester);

      await harness.tapButton(tester, 'Continue reading');

      expect(shownTrack(tester), ReadingTrack.plan);
      expect(find.text('0 of 4 ayat'), findsOneWidget);
      expect(find.text('Translation number 1.'), findsOneWidget);
    });

    testWidgets('tapped while the app is open also shows the goal',
        (WidgetTester tester) async {
      final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        scheduler: scheduler,
        now: today,
        initialPreferences: withPlan(),
      );
      await harness.pumpApp(tester);
      expect(shownTrack(tester), ReadingTrack.plan);

      scheduler.tap(
        const QuranDeepLink(editionId: 'test_edition', kind: ReminderKind.plan),
      );
      await harness.settle(tester);

      expect(find.text('Today’s goal'), findsOneWidget);
      expect(find.text('Continue reading'), findsOneWidget);
    });

    testWidgets('for a plan since stopped opens today, marking nothing',
        (WidgetTester tester) async {
      final TestHarness harness = await TestHarness.create(
        contentSource: hundred(),
        scheduler: FakeNotificationScheduler(
          launchDeepLink: const QuranDeepLink(
            editionId: 'test_edition',
            kind: ReminderKind.plan,
          ),
        ),
        now: today,
        initialPreferences: <String, Object>{
          ...withPlan(),
          'flutter.plan.kind': ReadingPlanKind.oneAyah.storageKey,
        },
      );
      await harness.pumpApp(tester);

      expect(find.text('Today’s Ayah'), findsOneWidget);
      expect(find.text('0 of 100 read'), findsOneWidget);
    });
  });

  testWidgets('the Daily Ayah’s reminder opens and marks the Daily Ayah',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: hundred(),
      scheduler: FakeNotificationScheduler(
        launchDeepLink: const QuranDeepLink(editionId: 'test_edition'),
      ),
      now: today,
      // The plan was on screen last; the reminder was not the plan's.
      initialPreferences: withPlan(track: 'plan'),
    );
    await harness.pumpApp(tester);

    expect(shownTrack(tester), ReadingTrack.daily);
    expect(find.text('1 of 100 read'), findsOneWidget);
    expect((await progressOf(tester, harness, 'quran')).totalRead, 1);
    expect((await progressOf(tester, harness, 'quran#plan')).totalRead, 0);
  });

  testWidgets('the Progress tab shows each reading on its own',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: hundred(),
      now: today,
      initialPreferences: withPlan(),
    );
    await harness.pumpApp(tester);
    await harness.tapButton(tester, 'Mark as read');
    await switchTo(tester, harness, 'Daily Ayah');
    await harness.tapButton(tester, 'Mark as read');

    await harness.goTo(tester, Routes.progress);

    expect(find.text('MY PLAN'), findsOneWidget);
    expect(find.text('DAILY AYAH'), findsOneWidget);
    expect(find.text('Finish by Feb 6, 2026'), findsOneWidget);
    expect(find.text('Today’s goal · 1 of 4 ayat'), findsOneWidget);
    expect(find.text('Whole Qur’an · 1 of 100'), findsOneWidget);

    // The plan card's button opens the plan, not the Daily Ayah last shown.
    final Finder planButton = find.widgetWithText(FilledButton, 'Continue reading');
    await tester.ensureVisible(planButton.first);
    await tester.pump();
    await tester.tap(planButton.first);
    await harness.settle(tester);
    expect(shownTrack(tester), ReadingTrack.plan);
  });

  testWidgets('without a plan, the Progress tab offers to make one',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: hundred(),
      now: today,
      initialPreferences: <String, Object>{
        ...withPlan(),
        'flutter.plan.kind': ReadingPlanKind.oneAyah.storageKey,
      },
    );
    await harness.pumpApp(tester);
    await harness.goTo(tester, Routes.progress);

    expect(find.text('Finish the whole Qur’an by a date'), findsOneWidget);
    await harness.tapButton(tester, 'Make a plan');
    expect(find.text('Choose the day you want to finish.'), findsOneWidget);
  });

  testWidgets('a plan from before plans had their own reading keeps its place',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: hundred(),
      now: today,
      initialPreferences: withPlan(legacy: true),
    );
    // Read as the old app did: the plan's reading on the Daily Ayah's scope.
    await tester.runAsync(() async {
      final ProgressDao dao = ProgressDao(harness.database);
      for (int ordinal = 1; ordinal <= 10; ordinal++) {
        await dao.markRead(
          'quran',
          '${((ordinal - 1) ~/ 10) + 1}:${((ordinal - 1) % 10) + 1}',
          ordinal,
          100,
          at: DateTime(2026, 1, 6, 10, 0),
        );
      }
    });

    await harness.pumpApp(tester);

    // The plan picks up exactly where it was, rather than at the first ayah.
    expect(shownTrack(tester), ReadingTrack.plan);
    expect(find.text('10 of 100 read'), findsOneWidget);
    expect(find.text('Translation number 11.'), findsOneWidget);
    // The Daily Ayah keeps its own copy, and the carry-over happens once.
    expect((await progressOf(tester, harness, 'quran')).totalRead, 10);
    expect(
      harness.container.read(userPreferencesProvider).plan.needsTrackSeed,
      isFalse,
    );
    final SharedPreferences prefs =
        harness.container.read(sharedPreferencesProvider);
    expect(prefs.getString('plan.track'), 'separate');
  });
}
