import 'package:daily_quran/app/providers.dart';
import 'package:daily_quran/app/routes.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// Word-by-word tarjama: each Arabic word with what it means on its own.
///
/// A reading aid, not a second translation — and only ever shown where the
/// installed edition actually carries glosses.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object> onboarded({bool wordByWord = false}) => <String, Object>{
        'flutter.pref.onboarding_complete': true,
        'flutter.pref.current_edition_id': 'test_edition',
        'flutter.pref.show_word_by_word': wordByWord,
        'flutter.notify.enabled': true,
        'flutter.notify.frequency': NotificationFrequency.daily.storageKey,
        'flutter.notify.time': '08:00',
      };

  testWidgets('is off by default', (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: FakeContentSource.single(count: 10, withWords: true),
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    expect(find.text('نص عربي رقم 1'), findsOneWidget);
    expect(find.text('word'), findsNothing);
  });

  testWidgets('turning it on shows each word with its meaning',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: FakeContentSource.single(count: 10, withWords: true),
      initialPreferences: onboarded(wordByWord: true),
    );
    await harness.pumpApp(tester);

    expect(find.text('كلمة'), findsOneWidget);
    expect(find.text('word'), findsOneWidget);
    expect(find.text('number 1'), findsOneWidget);

    // It stands in for the running Arabic rather than repeating it.
    expect(find.text('نص عربي رقم 1'), findsNothing);
    // The ayah's own translation is untouched: a gloss is not a substitute.
    expect(find.text('Translation number 1.'), findsOneWidget);
  });

  testWidgets('an edition with no glosses is unaffected',
      (WidgetTester tester) async {
    // Asking for something the installed edition does not have must never
    // blank out the Arabic.
    final TestHarness harness = await TestHarness.create(
      contentSource: FakeContentSource.single(count: 10),
      initialPreferences: onboarded(wordByWord: true),
    );
    await harness.pumpApp(tester);

    expect(find.text('نص عربي رقم 1'), findsOneWidget);
    expect(find.text('word'), findsNothing);
  });

  testWidgets('the setting can be turned on from reading settings',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: FakeContentSource.single(count: 10, withWords: true),
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);
    await harness.goTo(tester, Routes.settingsReading);

    final Finder toggle = find
        .ancestor(
          of: find.text('Show word by word'),
          matching: find.byType(Row),
        )
        .first;
    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(find.descendant(of: toggle, matching: find.byType(Switch)));
    await harness.settle(tester);

    expect(
      harness.container.read(userPreferencesProvider).showWordByWord,
      isTrue,
    );

    await harness.goTo(tester, Routes.today);
    expect(find.text('word'), findsOneWidget);
  });

  testWidgets('glosses follow the reader to the next ayah',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: FakeContentSource.single(count: 10, withWords: true),
      initialPreferences: onboarded(wordByWord: true),
    );
    await harness.pumpApp(tester);

    expect(find.text('number 1'), findsOneWidget);

    final Finder next = find.byTooltip('Next ayah');
    await tester.ensureVisible(next);
    await tester.pump();
    await tester.tap(next);
    await harness.settle(tester);

    expect(find.text('number 2'), findsOneWidget);
    expect(find.text('number 1'), findsNothing);
  });
}
