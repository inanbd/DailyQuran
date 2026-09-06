import 'package:daily_quran/app/providers.dart';
import 'package:daily_quran/domain/entities/ayah.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/entities/notification_preferences.dart';
import 'package:daily_quran/domain/entities/quran_edition.dart';
import 'package:daily_quran/domain/entities/reading_progress.dart';
import 'package:daily_quran/domain/repositories/notification_scheduler.dart';
import 'package:daily_quran/features/today/today_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// The journey the whole product is built around:
///
/// install → choose a translation → choose a reminder → read ayah 1 → next
/// morning the reminder arrives → tap it → ayah 2 → progress reads 2.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a first-time reader gets set up and reads in sequence',
      (WidgetTester tester) async {
    final FakeContentSource content = FakeContentSource.single(
      id: 'saheeh_international',
      title: 'Saheeh International',
      count: 6236,
      surahLength: 100,
    );
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler(
      status: NotificationPermissionStatus.notDetermined,
    );
    final TestHarness harness = await TestHarness.create(
      contentSource: content,
      scheduler: scheduler,
      now: DateTime(2026, 1, 7, 9, 0),
    );

    await harness.pumpApp(tester);

    // ---- Onboarding step 1 -------------------------------------------------
    expect(find.text('An ayah at a time'), findsOneWidget);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await harness.tapButton(tester, 'Continue');

    // ---- Step 2: choose the translation ------------------------------------
    expect(find.text('Choose your translation'), findsOneWidget);
    expect(find.text('Saheeh International'), findsOneWidget);
    await harness.tapButton(tester, 'Continue');

    // ---- Step 3: reminder, defaulting to 8:00 AM ---------------------------
    expect(find.text('Choose your reminder'), findsOneWidget);
    expect(find.text('8:00 AM'), findsOneWidget);
    expect(find.text('Arabic + translation'), findsOneWidget);

    // No OS prompt has been raised yet — permission is asked for at the end.
    expect(scheduler.permissionRequests, 0);

    await harness.tapButton(tester, 'Start reading');

    // Permission was requested once, after the reader chose their time.
    expect(scheduler.permissionRequests, 1);

    // Reminders were armed for the chosen edition at the chosen time.
    expect(scheduler.scheduledPreferences, isNotEmpty);
    final NotificationPreferences armed = scheduler.scheduledPreferences.last;
    expect(armed.enabled, isTrue);
    expect(armed.frequency, NotificationFrequency.daily);
    expect(armed.time, const TimeOfDayValue(8, 0));
    expect(scheduler.scheduledEditionIds.last, 'saheeh_international');

    // ---- Day 1: the first ayah --------------------------------------------
    expect(find.text('Today’s Ayah'), findsOneWidget);
    expect(find.textContaining('1:1'), findsWidgets);
    expect(find.text('Translation number 1.'), findsOneWidget);
    expect(find.text('نص عربي رقم 1'), findsOneWidget);
    expect(find.text('0 of 6,236 read'), findsOneWidget);

    await harness.tapButton(tester, 'Mark as read');

    expect(find.text('1 of 6,236 read'), findsOneWidget);
    // Still showing what was just read, not jumping ahead.
    expect(find.text('Translation number 1.'), findsOneWidget);

    // ---- Next morning: the reminder fires and is tapped --------------------
    harness.clock.advanceDays(1);

    // The reminder firing on its own changes nothing.
    expect(
      harness.container
          .read(todayControllerProvider)
          .value
          ?.progress
          ?.totalRead,
      1,
    );

    // Tapping it opens the app at the reader's current position.
    await harness.act(
      tester,
      () => harness.container
          .read(todayControllerProvider.notifier)
          .markReadFromNotification(),
    );

    expect(find.text('Translation number 2.'), findsOneWidget);
    expect(find.text('2 of 6,236 read'), findsOneWidget);

    // ---- Day 3 continues the sequence -------------------------------------
    harness.clock.advanceDays(1);
    await harness.act(
      tester,
      () => harness.container.read(todayControllerProvider.notifier).refresh(),
    );

    expect(find.text('Translation number 3.'), findsOneWidget);
    expect(find.text('2 of 6,236 read'), findsOneWidget);
  });

  testWidgets('missing several days resumes at the first unread ayah',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: FakeContentSource.single(count: 50),
      now: DateTime(2026, 1, 7, 9, 0),
      initialPreferences: _onboardedPreferences(),
    );
    await harness.pumpApp(tester);

    expect(find.text('Translation number 1.'), findsOneWidget);
    await harness.tapButton(tester, 'Mark as read');

    // Two weeks pass with the app unopened.
    harness.clock.advanceDays(14);
    await harness.act(
      tester,
      () => harness.container.read(todayControllerProvider.notifier).refresh(),
    );

    // Nothing was auto-marked; reading resumes at the second ayah.
    expect(find.text('Translation number 2.'), findsOneWidget);
    expect(find.text('1 of 50 read'), findsOneWidget);
  });

  testWidgets('skipping ahead does not mark the ayat passed over',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: FakeContentSource.single(count: 50),
      now: DateTime(2026, 1, 7, 9, 0),
      initialPreferences: _onboardedPreferences(),
    );
    await harness.pumpApp(tester);

    final TodayController controller =
        harness.container.read(todayControllerProvider.notifier);

    await harness.act(tester, controller.goToNext);
    await harness.act(tester, controller.goToNext);

    expect(find.text('Translation number 3.'), findsOneWidget);
    expect(find.text('0 of 50 read'), findsOneWidget);

    await harness.tapButton(tester, 'Mark as read');
    expect(find.text('1 of 50 read'), findsOneWidget);

    // Tomorrow picks up the first ayah, which was never read.
    harness.clock.advanceDays(1);
    await harness.act(tester, controller.refresh);
    expect(find.text('Translation number 1.'), findsOneWidget);
  });

  testWidgets('finishing shows the completion state',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: FakeContentSource.single(
        count: 3,
        title: 'Short Edition',
      ),
      now: DateTime(2026, 1, 7, 9, 0),
      initialPreferences: _onboardedPreferences(),
    );
    await harness.pumpApp(tester);

    final TodayController controller =
        harness.container.read(todayControllerProvider.notifier);
    for (int i = 1; i <= 3; i++) {
      await harness.act(tester, () => controller.goTo(i));
      await harness.act(tester, controller.markRead);
    }

    expect(find.text('Alhamdulillah'), findsOneWidget);
    expect(
      find.text('You completed the Qur’an, reading Short Edition.'),
      findsOneWidget,
    );
    expect(find.text('3 ayat read.'), findsOneWidget);

    // Reading again clears progress and returns to the first ayah.
    await harness.tapButton(tester, 'Read again from the beginning');

    expect(find.text('Translation number 1.'), findsOneWidget);
    expect(find.text('0 of 3 read'), findsOneWidget);
  });

  testWidgets('switching translation carries the reader’s place with it',
      (WidgetTester tester) async {
    // The behaviour that distinguishes this app from a shelf of separate
    // books: ayah 2:255 is the same ayah in every translation, so changing
    // translation must not restart anyone.
    final FakeContentSource english =
        FakeContentSource.single(id: 'english', title: 'English', count: 10);
    final FakeContentSource french = FakeContentSource.single(
      id: 'french',
      title: 'French',
      count: 10,
      languageCode: 'fr-FR',
      translationText: (int ordinal) => 'Traduction numéro $ordinal.',
    );
    final FakeContentSource content = FakeContentSource(
      editions: <QuranEdition>[...english.editions, ...french.editions],
      ayatByEdition: <String, List<Ayah>>{
        ...english.ayatByEdition,
        ...french.ayatByEdition,
      },
    );

    final TestHarness harness = await TestHarness.create(
      contentSource: content,
      now: DateTime(2026, 1, 7, 9, 0),
      initialPreferences: _onboardedPreferences(editionId: 'english'),
    );
    await harness.pumpApp(tester);

    final TodayController controller =
        harness.container.read(todayControllerProvider.notifier);
    await harness.act(tester, () => controller.goTo(4));
    await harness.act(tester, controller.markRead);
    expect(find.text('1 of 10 read'), findsOneWidget);
    expect(find.text('Translation number 4.'), findsOneWidget);

    // Switch to the French translation.
    await harness.act(
      tester,
      () => harness.container
          .read(userPreferencesProvider.notifier)
          .setCurrentEdition('french'),
    );

    // Same place, same progress — in the new translation.
    expect(find.text('Traduction numéro 4.'), findsOneWidget);
    expect(find.text('1 of 10 read'), findsOneWidget);

    final ReadingProgress? progress =
        harness.container.read(todayControllerProvider).value?.progress;
    expect(progress?.totalRead, 1);
    expect(progress?.currentOrdinal, 4);
  });

  testWidgets('the development fixture keeps its progress out of the Qur’an',
      (WidgetTester tester) async {
    final FakeContentSource fixture = FakeContentSource.single(
      id: 'dev_sample',
      title: 'Development Sample',
      count: 10,
      progressScope: 'dev_sample',
      verification: ContentVerification.developmentFixture,
    );
    final FakeContentSource real =
        FakeContentSource.single(id: 'english', title: 'English', count: 10);
    final FakeContentSource content = FakeContentSource(
      editions: <QuranEdition>[...fixture.editions, ...real.editions],
      ayatByEdition: <String, List<Ayah>>{
        ...fixture.ayatByEdition,
        ...real.ayatByEdition,
      },
    );

    final TestHarness harness = await TestHarness.create(
      contentSource: content,
      now: DateTime(2026, 1, 7, 9, 0),
      initialPreferences: _onboardedPreferences(editionId: 'dev_sample'),
    );
    await harness.pumpApp(tester);

    await harness.tapButton(tester, 'Mark as read');
    expect(find.text('1 of 10 read'), findsOneWidget);

    // Moving to a real edition starts from nothing: placeholder reading is not
    // reading the Qur'an.
    await harness.act(
      tester,
      () => harness.container
          .read(userPreferencesProvider.notifier)
          .setCurrentEdition('english'),
    );
    expect(find.text('0 of 10 read'), findsOneWidget);
  });
}

/// Preferences for a reader who has already been through onboarding.
Map<String, Object> _onboardedPreferences({
  String editionId = 'test_edition',
}) {
  return <String, Object>{
    'flutter.pref.onboarding_complete': true,
    'flutter.pref.current_edition_id': editionId,
    'flutter.pref.language_mode': LanguageMode.both.storageKey,
    'flutter.notify.enabled': true,
    'flutter.notify.frequency': NotificationFrequency.daily.storageKey,
    'flutter.notify.time': '08:00',
  };
}
