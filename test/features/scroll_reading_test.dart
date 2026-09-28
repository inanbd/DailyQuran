import 'package:daily_quran/app/routes.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/features/today/scroll_reading.dart';
import 'package:daily_quran/features/today/today_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// The Read tab as one continuous column. An ayah counts as read here the way
/// it does on a page — by being read, not by being passed — so the guard rails
/// are the same: nothing flicked past is marked, and the reader always has the
/// last word.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object> scrolling() => <String, Object>{
        'flutter.pref.onboarding_complete': true,
        'flutter.pref.current_edition_id': 'test_edition',
        'flutter.pref.reading_layout': ReadingLayout.scroll.storageKey,
        'flutter.notify.enabled': true,
        'flutter.notify.frequency': NotificationFrequency.daily.storageKey,
        'flutter.notify.time': '08:00',
      };

  ScrollPosition column(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  /// Scrolls so the ayah whose translation is [text] sits entirely above the
  /// column — read on past.
  Future<void> scrollPast(
    WidgetTester tester,
    TestHarness harness,
    String text,
  ) async {
    final double top = tester.getTopLeft(find.byType(CustomScrollView)).dy;
    final double bottom = tester.getBottomLeft(find.text(text)).dy;
    final ScrollPosition position = column(tester);
    // Past the translation, its actions and the rule beneath it.
    position.jumpTo(position.pixels + (bottom - top) + 120);
    await harness.settle(tester);
  }

  testWidgets('the ayat run on one after another, surah after surah',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      initialPreferences: scrolling(),
    );
    await harness.pumpApp(tester);

    expect(find.byType(ScrollReading), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(find.text('Translation number 1.'), findsOneWidget);

    // The test edition's second surah begins at its sixth ayah. Scrolled a
    // step at a time, letting each step's ayat load, the way a reader would.
    final Finder sixth = find.text('Translation number 6.');
    for (int step = 0; step < 20 && sixth.evaluate().isEmpty; step++) {
      final ScrollPosition position = column(tester);
      position.jumpTo(position.pixels + 250);
      await harness.settle(tester);
    }
    expect(sixth, findsOneWidget);
    expect(find.text('Surah 2'), findsWidgets);
  });

  testWidgets('an ayah read and then scrolled past is marked read',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      initialPreferences: scrolling(),
    );
    await harness.pumpApp(tester);
    expect(find.text('0 of 10 read'), findsOneWidget);

    // Time with it on screen...
    await tester.pump(const Duration(seconds: 10));
    await harness.settle(tester);
    expect(find.text('0 of 10 read'), findsOneWidget,
        reason: 'still on screen: not read on past yet');

    // ...and then on past it.
    await scrollPast(tester, harness, 'Translation number 1.');
    expect(find.text('1 of 10 read'), findsOneWidget);
  });

  testWidgets('flicking straight past marks nothing',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      initialPreferences: scrolling(),
    );
    await harness.pumpApp(tester);

    await scrollPast(tester, harness, 'Translation number 1.');
    await tester.pump(const Duration(seconds: 10));
    await harness.settle(tester);

    expect(find.text('0 of 10 read'), findsOneWidget);
  });

  testWidgets('the tick marks by hand, and an ayah unmarked stays unmarked',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      initialPreferences: scrolling(),
    );
    await harness.pumpApp(tester);

    await tester.tap(find.byTooltip('Mark 1:1 as read'));
    await harness.settle(tester);
    expect(find.text('1 of 10 read'), findsOneWidget);

    await tester.tap(find.byTooltip('Mark 1:1 as unread'));
    await harness.settle(tester);
    expect(find.text('0 of 10 read'), findsOneWidget);

    // Read through and scrolled past, it would have marked itself — but the
    // reader said otherwise, and their word stands.
    await tester.pump(const Duration(seconds: 10));
    await scrollPast(tester, harness, 'Translation number 1.');
    expect(find.text('0 of 10 read'), findsOneWidget);
  });

  testWidgets('the place is kept where the reader stops',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      initialPreferences: scrolling(),
    );
    await harness.pumpApp(tester);

    await scrollPast(tester, harness, 'Translation number 1.');
    await scrollPast(tester, harness, 'Translation number 2.');
    // Once the column has been still a moment.
    await tester.pump(const Duration(seconds: 1));
    await harness.settle(tester);

    final TodayState state = harness.container.read(todayControllerProvider).value!;
    expect(state.ordinal, 3);
    expect(find.text('Surah 1 · 1:3'), findsOneWidget);
    // Browsing is not reading: nothing was marked on the way.
    expect(find.text('0 of 10 read'), findsOneWidget);
  });

  testWidgets('the setting switches the Read tab between swiping and scrolling',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      initialPreferences: <String, Object>{
        ...scrolling(),
        'flutter.pref.reading_layout': ReadingLayout.swipe.storageKey,
      },
    );
    await harness.pumpApp(tester);
    expect(find.byType(PageView), findsOneWidget);

    await harness.goTo(tester, Routes.settingsReading);
    final Finder scroll = find.text('Scroll, one after another');
    await tester.ensureVisible(scroll);
    await tester.pump();
    await tester.tap(scroll);
    await harness.settle(tester);
    await harness.goTo(tester, Routes.today);

    expect(find.byType(ScrollReading), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(find.text('Translation number 1.'), findsOneWidget);
  });
}
