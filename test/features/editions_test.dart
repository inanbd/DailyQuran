import 'package:daily_quran/app/providers.dart';
import 'package:daily_quran/domain/entities/ayah.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/entities/quran_edition.dart';
import 'package:daily_quran/features/today/today_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// Choosing which translation to read, from the reading screen.
///
/// Switching has to be cheap and lossless, because that is the whole reason the
/// app stores progress against the ayah rather than the translator.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object> onboarded({String editionId = 'english'}) =>
      <String, Object>{
        'flutter.pref.onboarding_complete': true,
        'flutter.pref.current_edition_id': editionId,
        'flutter.notify.enabled': true,
        'flutter.notify.frequency': NotificationFrequency.daily.storageKey,
        'flutter.notify.time': '08:00',
      };

  /// Three editions: two translations of the Qur'an and one that is not.
  FakeContentSource library({bool includeFixture = false}) {
    final FakeContentSource english = FakeContentSource.single(
      id: 'english',
      title: 'Saheeh International',
      count: 10,
    );
    final FakeContentSource urdu = FakeContentSource.single(
      id: 'urdu',
      title: 'Maududi (Urdu)',
      count: 10,
      languageCode: 'ur-PK',
      isRightToLeft: true,
      translationText: (int ordinal) => 'اردو ترجمہ نمبر $ordinal۔',
    );
    final FakeContentSource fixture = FakeContentSource.single(
      id: 'dev_sample',
      title: 'Development Sample',
      count: 10,
      progressScope: 'dev_sample',
      verification: ContentVerification.developmentFixture,
    );

    return FakeContentSource(
      editions: <QuranEdition>[
        ...english.editions,
        ...urdu.editions,
        if (includeFixture) ...fixture.editions,
      ],
      ayatByEdition: <String, List<Ayah>>{
        ...english.ayatByEdition,
        ...urdu.ayatByEdition,
        if (includeFixture) ...fixture.ayatByEdition,
      },
    );
  }

  testWidgets('the translation being read is named on the reading screen',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: library(),
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    expect(find.text('Saheeh International'), findsOneWidget);
  });

  testWidgets('tapping it offers every translation that can be opened',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: library(),
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    await tester.tap(find.text('Saheeh International'));
    await harness.settle(tester);

    expect(find.text('Translation'), findsOneWidget);
    expect(find.text('Maududi (Urdu)'), findsOneWidget);
    // The one being read is listed too, marked as current.
    expect(find.text('Saheeh International'), findsWidgets);
  });

  testWidgets('choosing another translation keeps the reader in place',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: library(),
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    final TodayController controller =
        harness.container.read(todayControllerProvider.notifier);
    await harness.act(tester, () => controller.goTo(4));
    await harness.act(tester, controller.markRead);
    expect(find.text('Translation number 4.'), findsOneWidget);
    expect(find.text('1 of 10 read'), findsOneWidget);

    await tester.tap(find.text('Saheeh International'));
    await harness.settle(tester);
    await tester.tap(find.text('Maududi (Urdu)'));
    await harness.settle(tester);

    // The sheet closed, the ayah is the same one, and nothing was lost.
    expect(find.text('اردو ترجمہ نمبر 4۔'), findsOneWidget);
    expect(find.text('1 of 10 read'), findsOneWidget);
    expect(
      harness.container.read(userPreferencesProvider).currentEditionId,
      'urdu',
    );
  });

  testWidgets('switching re-arms the reminder for the new edition',
      (WidgetTester tester) async {
    // Reminders deep-link into an edition, so one armed for the old one would
    // send the reader somewhere they no longer read.
    final FakeNotificationScheduler scheduler = FakeNotificationScheduler();
    final TestHarness harness = await TestHarness.create(
      contentSource: library(),
      scheduler: scheduler,
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);
    expect(scheduler.scheduledEditionIds.last, 'english');

    await tester.tap(find.text('Saheeh International'));
    await harness.settle(tester);
    await tester.tap(find.text('Maududi (Urdu)'));
    await harness.settle(tester);

    expect(scheduler.scheduledEditionIds.last, 'urdu');
  });

  testWidgets('the development fixture is flagged in the chooser',
      (WidgetTester tester) async {
    // A verified edition is readable here, so the fixture is hidden from the
    // library entirely — and must not reappear in this list either.
    final TestHarness harness = await TestHarness.create(
      contentSource: library(includeFixture: true),
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    await tester.tap(find.text('Saheeh International'));
    await harness.settle(tester);

    expect(find.text('Development Sample'), findsNothing);
  });
}
