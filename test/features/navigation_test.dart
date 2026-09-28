import 'package:daily_quran/app/routes.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/features/favourites/favourites_screen.dart';
import 'package:daily_quran/features/library/edition_details_screen.dart';
import 'package:daily_quran/features/library/library_screen.dart';
import 'package:daily_quran/features/progress/progress_screen.dart';
import 'package:daily_quran/features/settings/about_screen.dart';
import 'package:daily_quran/features/settings/appearance_settings_screen.dart';
import 'package:daily_quran/features/settings/notification_settings_screen.dart';
import 'package:daily_quran/features/settings/reading_settings_screen.dart';
import 'package:daily_quran/features/settings/settings_screen.dart';
import 'package:daily_quran/features/today/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// Every screen must render, in both themes and at the largest text size,
/// without layout errors — a widget test fails on any overflow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object> onboarded({
    String textSize = 'standard',
    String theme = 'system',
  }) =>
      <String, Object>{
        'flutter.pref.onboarding_complete': true,
        'flutter.pref.current_edition_id': 'test_edition',
        'flutter.pref.text_size': textSize,
        'flutter.pref.theme_mode': theme,
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

  testWidgets('every tab and settings screen renders',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    expect(find.byType(TodayScreen), findsOneWidget);

    await go(tester, harness, Routes.library);
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.text('Translations'), findsOneWidget);

    await go(tester, harness, Routes.edition('test_edition'));
    expect(find.byType(EditionDetailsScreen), findsOneWidget);
    expect(find.text('SOURCE'), findsOneWidget);

    await go(tester, harness, Routes.favourites);
    expect(find.byType(FavouritesScreen), findsOneWidget);

    await go(tester, harness, Routes.progress);
    expect(find.byType(ProgressScreen), findsOneWidget);
    expect(find.text('Your Progress'), findsOneWidget);

    await go(tester, harness, Routes.settings);
    expect(find.byType(SettingsScreen), findsOneWidget);

    await go(tester, harness, Routes.settingsNotifications);
    expect(find.byType(NotificationSettingsScreen), findsOneWidget);
    expect(find.text('NEXT REMINDERS'), findsOneWidget);

    await go(tester, harness, Routes.settingsReading);
    expect(find.byType(ReadingSettingsScreen), findsOneWidget);

    await go(tester, harness, Routes.settingsAppearance);
    expect(find.byType(AppearanceSettingsScreen), findsOneWidget);
    expect(find.text('PREVIEW'), findsOneWidget);

    await go(tester, harness, Routes.settingsAbout);
    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text('PRIVACY'), findsOneWidget);
    expect(find.text('RECITATION'), findsOneWidget);
  });

  testWidgets('the bottom navigation bar moves between tabs',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    await tester.tap(find.text('Library'));
    await harness.settle(tester);
    expect(find.byType(LibraryScreen), findsOneWidget);

    await tester.tap(find.text('Favourites'));
    await harness.settle(tester);
    expect(find.byType(FavouritesScreen), findsOneWidget);

    await tester.tap(find.text('Progress'));
    await harness.settle(tester);
    expect(find.byType(ProgressScreen), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await harness.settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.tap(find.text('Read'));
    await harness.settle(tester);
    expect(find.byType(TodayScreen), findsOneWidget);
  });

  testWidgets('the tabs run Read, Progress, Library, Favourites, Settings',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    final List<String> labels = <String>[
      'Read',
      'Progress',
      'Library',
      'Favourites',
      'Settings',
    ];
    final List<double> positions = <double>[
      for (final String label in labels)
        tester
            .getCenter(
              find.descendant(
                of: find.byType(NavigationBar),
                matching: find.text(label),
              ),
            )
            .dx,
    ];
    expect(positions, orderedEquals(<double>[...positions]..sort()));

    // The second tab is the one that opens Progress.
    await tester.tap(find.text('Progress'));
    await harness.settle(tester);
    expect(find.byType(ProgressScreen), findsOneWidget);
  });

  testWidgets('renders in dark mode at the largest text size',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final TestHarness harness = await TestHarness.create(
      initialPreferences: onboarded(textSize: 'extra_large', theme: 'dark'),
    );
    await harness.pumpApp(tester);

    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text('Translation number 1.'), findsOneWidget);

    await go(tester, harness, Routes.library);
    expect(find.byType(LibraryScreen), findsOneWidget);

    await go(tester, harness, Routes.settings);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('renders on a small screen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final TestHarness harness = await TestHarness.create(
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);
    expect(find.byType(TodayScreen), findsOneWidget);
  });

  testWidgets('the development fixture is flagged wherever it is shown',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: FakeContentSource.single(
        id: 'fixture_edition',
        title: 'Fixture Edition',
        progressScope: 'fixture_edition',
        verification: ContentVerification.developmentFixture,
      ),
      initialPreferences: <String, Object>{
        ...onboarded(),
        'flutter.pref.current_edition_id': 'fixture_edition',
      },
    );
    await harness.pumpApp(tester);

    expect(find.text('Development data'), findsOneWidget);
    expect(
      find.textContaining('not the Qur’an'),
      findsWidgets,
      reason: 'placeholder content must say so on the reading screen',
    );

    await go(tester, harness, Routes.library);
    expect(find.text('Development data'), findsWidgets);
  });

  testWidgets('swiping turns the page, the way a gallery does',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    expect(find.text('Translation number 1.'), findsOneWidget);

    // Swiping right at the start has nowhere to go.
    await tester.fling(find.byType(PageView), const Offset(400, 0), 1200);
    await harness.settle(tester);
    expect(find.text('Translation number 1.'), findsOneWidget);

    // Left carries the reader forward.
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await harness.settle(tester);
    expect(find.text('Translation number 2.'), findsOneWidget);
    expect(find.text('Translation number 1.'), findsNothing);

    // Right takes them back.
    await tester.fling(find.byType(PageView), const Offset(400, 0), 1200);
    await harness.settle(tester);
    expect(find.text('Translation number 1.'), findsOneWidget);

    // Turning pages is browsing: nothing on the way was marked read.
    expect(find.text('0 of 10 read'), findsOneWidget);
  });

  testWidgets('the page follows the finger, and settles the way a gallery does',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    // Partway through a drag, both ayat are on screen at once: the next page
    // slides in beneath the finger rather than appearing when it lifts.
    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(find.byType(PageView)));
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-200, 0));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text('Translation number 1.'), findsOneWidget);
    expect(find.text('Translation number 2.'), findsOneWidget);

    // Let go short of halfway, slowly, and it springs back.
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await harness.settle(tester);
    expect(find.text('Translation number 1.'), findsOneWidget);
    expect(find.text('Translation number 2.'), findsNothing);

    // Past halfway, however slowly, and the page turns.
    await tester.timedDrag(
      find.byType(PageView),
      const Offset(-500, 0),
      const Duration(seconds: 2),
    );
    await harness.settle(tester);
    expect(find.text('Translation number 2.'), findsOneWidget);

    // A long drag is a long run of touches, each of them reading time to
    // record; let that finish before the test does.
    await harness.settle(tester);
  });

  testWidgets('the arrows slide the carousel, and Mark as read carries on',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    await tester.tap(find.byTooltip('Next ayah'));
    await harness.settle(tester);
    expect(find.text('Translation number 2.'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous ayah'));
    await harness.settle(tester);
    expect(find.text('Translation number 1.'), findsOneWidget);

    // The Daily Ayah is one ayah, so reading it stays on it...
    await harness.tapButton(tester, 'Mark as read');
    expect(find.text('Translation number 1.'), findsOneWidget);
    expect(find.text('1 of 10 read'), findsOneWidget);
  });
}
