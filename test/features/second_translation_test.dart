import 'package:daily_quran/app/providers.dart';
import 'package:daily_quran/app/routes.dart';
import 'package:daily_quran/domain/entities/ayah.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/entities/quran_edition.dart';
import 'package:daily_quran/domain/entities/reading_plan.dart';
import 'package:daily_quran/domain/entities/reading_track.dart';
import 'package:daily_quran/domain/entities/user_preferences.dart';
import 'package:daily_quran/features/today/today_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// Reading two translations of the same ayah at once.
///
/// The cap is two, and the pair has to stay one ayah: the same reading
/// position, the same mark-as-read, the same saved ayat.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object> onboarded({
    String? second,
    ReadingPlanKind plan = ReadingPlanKind.oneAyah,
  }) =>
      <String, Object>{
        'flutter.pref.onboarding_complete': true,
        'flutter.pref.current_edition_id': 'english',
        if (second case final String id) 'flutter.pref.secondary_edition_id': id,
        'flutter.notify.enabled': true,
        'flutter.notify.frequency': NotificationFrequency.daily.storageKey,
        'flutter.notify.time': '08:00',
        'flutter.plan.kind': plan.storageKey,
      };

  /// Two translations of the Qur'an, plus one edition that is not the Qur'an.
  FakeContentSource library() {
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
        ...fixture.editions,
      ],
      ayatByEdition: <String, List<Ayah>>{
        ...english.ayatByEdition,
        ...urdu.ayatByEdition,
        ...fixture.ayatByEdition,
      },
    );
  }

  testWidgets('one translation shows on its own', (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: library(),
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    expect(find.text('Translation number 1.'), findsOneWidget);
    expect(find.text('اردو ترجمہ نمبر 1۔'), findsNothing);
    // No heading either: a lone translation needs no label to tell it apart.
    expect(find.text('MAUDUDI (URDU)'), findsNothing);
  });

  testWidgets('a second translation reads under the first, and is named',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: library(),
      initialPreferences: onboarded(second: 'urdu'),
    );
    await harness.pumpApp(tester);

    // The same ayah, twice, in the order the reader chose.
    expect(find.text('Translation number 1.'), findsOneWidget);
    expect(find.text('اردو ترجمہ نمبر 1۔'), findsOneWidget);
    // Named, because two unlabelled translations are just a repetition.
    expect(find.text('MAUDUDI (URDU)'), findsOneWidget);
  });

  testWidgets('the plan’s reading shows the second translation too',
      (WidgetTester tester) async {
    // The plan reads under a scope of its own, but it is the same ayat as the
    // translation beneath it — so the pair must survive the switch.
    final TestHarness harness = await TestHarness.create(
      contentSource: library(),
      initialPreferences: <String, Object>{
        ...onboarded(second: 'urdu', plan: ReadingPlanKind.oneMonth),
        'flutter.plan.track': 'separate',
      },
    );
    await harness.pumpApp(tester);

    expect(shownTrack(tester), ReadingTrack.plan);
    expect(find.text('Translation number 1.'), findsOneWidget);
    expect(find.text('اردو ترجمہ نمبر 1۔'), findsOneWidget);
    expect(find.text('MAUDUDI (URDU)'), findsOneWidget);
  });

  testWidgets('both translations move together through the reading',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: library(),
      initialPreferences: onboarded(second: 'urdu'),
    );
    await harness.pumpApp(tester);

    await harness.tapButton(tester, 'Mark as read');

    // One mark-as-read is one ayah, not two. Reading the same ayah in two
    // translations is still reading it once.
    expect(find.text('1 of 10 read'), findsOneWidget);

    await harness.act(
      tester,
      () => harness.container.read(todayControllerProvider.notifier).goToNext(),
    );

    // Both columns step together — never one ayah in one translation and a
    // different one in the other.
    expect(find.text('Translation number 2.'), findsOneWidget);
    expect(find.text('اردو ترجمہ نمبر 2۔'), findsOneWidget);
    expect(find.text('Translation number 1.'), findsNothing);
  });

  testWidgets('choosing a second translation takes effect on the reading',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: library(),
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);
    await harness.goTo(tester, Routes.settingsSecondTranslation);

    await harness.act(
      tester,
      () => harness.container
          .read(userPreferencesProvider.notifier)
          .setSecondaryEdition('urdu'),
    );
    await harness.goTo(tester, Routes.today);

    expect(find.text('اردو ترجمہ نمبر 1۔'), findsOneWidget);
  });

  testWidgets('turning the second translation off leaves one',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: library(),
      initialPreferences: onboarded(second: 'urdu'),
    );
    await harness.pumpApp(tester);

    expect(find.text('اردو ترجمہ نمبر 1۔'), findsOneWidget);

    await harness.act(
      tester,
      () => harness.container
          .read(userPreferencesProvider.notifier)
          .setSecondaryEdition(null),
    );

    expect(find.text('اردو ترجمہ نمبر 1۔'), findsNothing);
    expect(find.text('Translation number 1.'), findsOneWidget);
  });

  testWidgets('opening the second translation as the first one drops the pair',
      (WidgetTester tester) async {
    // Otherwise the reader ends up with the same translation stacked on
    // itself, which is a bug wearing the shape of a feature.
    final TestHarness harness = await TestHarness.create(
      contentSource: library(),
      initialPreferences: onboarded(second: 'urdu'),
    );
    await harness.pumpApp(tester);

    await harness.act(
      tester,
      () => harness.container
          .read(userPreferencesProvider.notifier)
          .setCurrentEdition('urdu'),
    );

    final UserPreferences preferences =
        harness.container.read(userPreferencesProvider);
    expect(preferences.currentEditionId, 'urdu');
    expect(preferences.secondaryEditionId, isNull);
    expect(preferences.editionIds, <String>['urdu']);
  });

  testWidgets('asking for the translation already on top is asking for one',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: library(),
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    await harness.act(
      tester,
      () => harness.container
          .read(userPreferencesProvider.notifier)
          .setSecondaryEdition('english'),
    );

    expect(
      harness.container.read(userPreferencesProvider).secondaryEditionId,
      isNull,
    );
  });

  testWidgets('a second translation from another reading is refused',
      (WidgetTester tester) async {
    // The development fixture keeps its own scope, so its ordinals are not the
    // Qur'an's. Pairing it with one would put an unrelated ayah underneath.
    final TestHarness harness = await TestHarness.create(
      contentSource: library(),
      initialPreferences: onboarded(second: 'dev_sample'),
    );
    await harness.pumpApp(tester);

    final TodayState state =
        harness.container.read(todayControllerProvider).value!;
    expect(state.secondaryEdition, isNull);
    expect(state.hasSecondTranslation, isFalse);
    expect(find.text('Translation number 1.'), findsOneWidget);
  });

  testWidgets('a second translation survives a restart',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: library(),
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    await harness.act(
      tester,
      () => harness.container
          .read(userPreferencesProvider.notifier)
          .setSecondaryEdition('urdu'),
    );

    final TestHarness restarted = await TestHarness.create(
      contentSource: library(),
      initialPreferences: <String, Object>{
        ...onboarded(),
        'flutter.pref.secondary_edition_id': 'urdu',
      },
    );
    await restarted.pumpApp(tester);

    expect(find.text('اردو ترجمہ نمبر 1۔'), findsOneWidget);
  });
}
