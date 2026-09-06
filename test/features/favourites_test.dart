import 'package:daily_quran/app/providers.dart';
import 'package:daily_quran/app/routes.dart';
import 'package:daily_quran/domain/entities/ayah.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/entities/quran_edition.dart';
import 'package:daily_quran/features/favourites/favourites_screen.dart';
import 'package:daily_quran/shared/widgets/ayah_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object> onboarded({String editionId = 'test_edition'}) =>
      <String, Object>{
        'flutter.pref.onboarding_complete': true,
        'flutter.pref.current_edition_id': editionId,
        'flutter.notify.enabled': true,
        'flutter.notify.frequency': NotificationFrequency.daily.storageKey,
        'flutter.notify.time': '08:00',
      };

  Future<void> go(
    WidgetTester tester,
    TestHarness harness,
    String location,
  ) async {
    final BuildContext context = tester.element(find.byType(Scaffold).first);
    context.go(location);
    await harness.settle(tester);
  }

  Future<void> tapAction(
    WidgetTester tester,
    TestHarness harness,
    String tooltip,
  ) async {
    final Finder finder = find.byTooltip(tooltip).first;
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(finder);
    });
    await harness.settle(tester);
  }

  testWidgets('the favourites tab starts empty', (WidgetTester tester) async {
    final TestHarness harness =
        await TestHarness.create(initialPreferences: onboarded());
    await harness.pumpApp(tester);

    await go(tester, harness, Routes.favourites);

    expect(find.byType(FavouritesScreen), findsOneWidget);
    expect(find.text('No favourites yet'), findsOneWidget);
  });

  testWidgets('an ayah saved from Today shows up under Favourites',
      (WidgetTester tester) async {
    final TestHarness harness =
        await TestHarness.create(initialPreferences: onboarded());
    await harness.pumpApp(tester);

    // The heart on today's ayah starts empty, then fills once tapped.
    expect(find.byTooltip('Save to favourites'), findsOneWidget);
    await tapAction(tester, harness, 'Save to favourites');
    expect(find.byTooltip('Remove from favourites'), findsOneWidget);

    await go(tester, harness, Routes.favourites);

    expect(find.text('No favourites yet'), findsNothing);
    expect(find.text('1 saved ayah'), findsOneWidget);
    expect(find.byType(AyahView), findsOneWidget);
  });

  testWidgets('unsaving from the favourites list empties it',
      (WidgetTester tester) async {
    final TestHarness harness =
        await TestHarness.create(initialPreferences: onboarded());
    await harness.pumpApp(tester);

    await tapAction(tester, harness, 'Save to favourites');
    await go(tester, harness, Routes.favourites);
    expect(find.text('1 saved ayah'), findsOneWidget);

    // The heart is already filled here, so tapping it removes the entry.
    await tapAction(tester, harness, 'Remove from favourites');

    expect(find.text('No favourites yet'), findsOneWidget);
  });

  testWidgets('favourites are kept per ayah', (WidgetTester tester) async {
    final TestHarness harness =
        await TestHarness.create(initialPreferences: onboarded());
    await harness.pumpApp(tester);

    await tapAction(tester, harness, 'Save to favourites');
    // Move to the next ayah: its heart must be empty again.
    await tapAction(tester, harness, 'Next ayah');
    expect(find.byTooltip('Save to favourites'), findsOneWidget);

    await tapAction(tester, harness, 'Save to favourites');
    await go(tester, harness, Routes.favourites);

    expect(find.text('2 saved ayat'), findsOneWidget);
  });

  testWidgets('a saved ayah follows the reader into another translation',
      (WidgetTester tester) async {
    // Favourites are stored by verse key, so they survive a change of
    // translation and are re-rendered in the one being read now.
    final FakeContentSource english =
        FakeContentSource.single(id: 'english', title: 'English', count: 10);
    final FakeContentSource french = FakeContentSource.single(
      id: 'french',
      title: 'French',
      count: 10,
      languageCode: 'fr-FR',
      translationText: (int ordinal) => 'Traduction numéro $ordinal.',
    );
    final TestHarness harness = await TestHarness.create(
      contentSource: FakeContentSource(
        editions: <QuranEdition>[...english.editions, ...french.editions],
        ayatByEdition: <String, List<Ayah>>{
          ...english.ayatByEdition,
          ...french.ayatByEdition,
        },
      ),
      initialPreferences: onboarded(editionId: 'english'),
    );
    await harness.pumpApp(tester);

    await tapAction(tester, harness, 'Save to favourites');
    await go(tester, harness, Routes.favourites);
    expect(find.text('Translation number 1.'), findsOneWidget);

    await harness.act(
      tester,
      () => harness.container
          .read(userPreferencesProvider.notifier)
          .setCurrentEdition('french'),
    );

    expect(find.text('1 saved ayah'), findsOneWidget);
    expect(find.text('Traduction numéro 1.'), findsOneWidget);
    expect(find.text('Translation number 1.'), findsNothing);
  });

  testWidgets('the five-tab bar and favourites render at the largest text size',
      (WidgetTester tester) async {
    // Five destinations is the point where the navigation bar is most likely
    // to overflow, so this checks the widest labels at the biggest type.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final TestHarness harness = await TestHarness.create(
      initialPreferences: <String, Object>{
        ...onboarded(),
        'flutter.pref.text_size': 'extra_large',
        'flutter.pref.theme_mode': 'dark',
      },
    );
    await harness.pumpApp(tester);

    await tapAction(tester, harness, 'Save to favourites');
    await go(tester, harness, Routes.favourites);

    expect(find.byType(FavouritesScreen), findsOneWidget);
    expect(find.text('1 saved ayah'), findsOneWidget);
  });
}
