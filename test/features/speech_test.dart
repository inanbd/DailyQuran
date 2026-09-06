import 'package:daily_quran/app/providers.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// Only the translation is ever spoken. Recitation of the Qur'an is its own
/// discipline, with rules a text-to-speech engine neither knows nor follows,
/// so there is no control anywhere in the app that reads the Arabic aloud.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object> onboarded() => <String, Object>{
        'flutter.pref.onboarding_complete': true,
        'flutter.pref.current_edition_id': 'test_edition',
        'flutter.notify.enabled': true,
        'flutter.notify.frequency': NotificationFrequency.daily.storageKey,
        'flutter.notify.time': '08:00',
      };

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

  testWidgets('pressing listen speaks the translation',
      (WidgetTester tester) async {
    final FakeSpeechSynthesizer speech = FakeSpeechSynthesizer();
    final TestHarness harness = await TestHarness.create(
      initialPreferences: onboarded(),
      speech: speech,
    );
    await harness.pumpApp(tester);

    await tapAction(tester, harness, 'Listen to the translation');

    expect(speech.spoken, hasLength(1));
    // The translation is what is read aloud, never the Arabic.
    expect(speech.spoken.single, contains('Translation'));
    expect(speech.spoken.single, isNot(contains('عربي')));
    expect(speech.languages.single, 'en-US');
  });

  testWidgets('the Arabic is never offered to a synthetic voice',
      (WidgetTester tester) async {
    final FakeSpeechSynthesizer speech = FakeSpeechSynthesizer();
    final TestHarness harness = await TestHarness.create(
      initialPreferences: onboarded(),
      speech: speech,
    );
    await harness.pumpApp(tester);

    expect(find.byTooltip('Listen to the Arabic'), findsNothing);

    // Even with the translation hidden, the Arabic gets no listen control.
    await harness.act(
      tester,
      () async => harness.container
          .read(userPreferencesProvider.notifier)
          .update(
            harness.container
                .read(userPreferencesProvider)
                .copyWith(languageMode: LanguageMode.arabic),
          ),
    );
    expect(find.byTooltip('Listen to the Arabic'), findsNothing);
    expect(find.byTooltip('Listen to the translation'), findsNothing);
    expect(speech.spoken, isEmpty);
  });

  testWidgets('no listen button when the device has no voice for the language',
      (WidgetTester tester) async {
    final FakeSpeechSynthesizer speech =
        FakeSpeechSynthesizer(available: false);
    final TestHarness harness = await TestHarness.create(
      initialPreferences: onboarded(),
      speech: speech,
    );
    await harness.pumpApp(tester);

    expect(find.byTooltip('Listen to the translation'), findsNothing);
    // The favourite control is unaffected by a missing voice.
    expect(find.byTooltip('Save to favourites'), findsOneWidget);
  });

  testWidgets('an edition is spoken in its own language',
      (WidgetTester tester) async {
    // A French translation must not be read out by an English voice.
    final FakeSpeechSynthesizer speech = FakeSpeechSynthesizer();
    final TestHarness harness = await TestHarness.create(
      contentSource: FakeContentSource.single(
        id: 'test_edition',
        languageCode: 'fr-FR',
        translationText: (int ordinal) => 'Traduction numéro $ordinal.',
      ),
      initialPreferences: onboarded(),
      speech: speech,
    );
    await harness.pumpApp(tester);

    await tapAction(tester, harness, 'Listen to the translation');

    expect(speech.languages.single, 'fr-FR');
    expect(speech.spoken.single, 'Traduction numéro 1.');
  });

  testWidgets('while speaking the button offers to stop',
      (WidgetTester tester) async {
    final FakeSpeechSynthesizer speech =
        FakeSpeechSynthesizer(completeManually: true);
    final TestHarness harness = await TestHarness.create(
      initialPreferences: onboarded(),
      speech: speech,
    );
    await harness.pumpApp(tester);

    await tapAction(tester, harness, 'Listen to the translation');

    expect(find.byTooltip('Stop reading aloud'), findsOneWidget);
    expect(find.byTooltip('Listen to the translation'), findsNothing);

    await tapAction(tester, harness, 'Stop reading aloud');

    expect(speech.stopCalls, greaterThan(0));
    expect(find.byTooltip('Listen to the translation'), findsOneWidget);
  });

  testWidgets('moving to another ayah speaks that one',
      (WidgetTester tester) async {
    final FakeSpeechSynthesizer speech = FakeSpeechSynthesizer();
    final TestHarness harness = await TestHarness.create(
      initialPreferences: onboarded(),
      speech: speech,
    );
    await harness.pumpApp(tester);

    await tapAction(tester, harness, 'Listen to the translation');
    await tapAction(tester, harness, 'Next ayah');
    await tapAction(tester, harness, 'Listen to the translation');

    expect(speech.spoken, hasLength(2));
    expect(speech.spoken.first, isNot(speech.spoken.last));
  });
}
