import 'package:daily_quran/domain/entities/ayah.dart';
import 'package:daily_quran/domain/entities/ayah_word.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/shared/theme/app_theme.dart';
import 'package:daily_quran/shared/widgets/ayah_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const Ayah full = Ayah(
    id: 'e:2:255',
    editionId: 'e',
    ordinal: 262,
    surahNumber: 2,
    ayahNumber: 255,
    surahNameEnglish: 'Al-Baqarah',
    arabicText: 'النص العربي',
    translationText: 'The translated line.',
    transliteration: 'An-nass al-arabi',
    juz: 3,
    page: 42,
    reference: 'Al-Baqarah 2:255',
  );

  Future<void> pumpView(
    WidgetTester tester,
    Ayah ayah,
    LanguageMode mode, {
    double scale = 1.0,
    bool showTransliteration = false,
    bool showWordByWord = false,
    bool translationIsRightToLeft = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AyahView(
              ayah: ayah,
              languageMode: mode,
              textScale: scale,
              showTransliteration: showTransliteration,
              showWordByWord: showWordByWord,
              translationIsRightToLeft: translationIsRightToLeft,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows Arabic above the translation when both are selected',
      (WidgetTester tester) async {
    await pumpView(tester, full, LanguageMode.both);

    expect(find.text('النص العربي'), findsOneWidget);
    expect(find.text('The translated line.'), findsOneWidget);

    // Arabic sits above the translation.
    final double arabicY = tester.getTopLeft(find.text('النص العربي')).dy;
    final double translationY =
        tester.getTopLeft(find.text('The translated line.')).dy;
    expect(arabicY, lessThan(translationY));

    // And is separated by the divider.
    expect(find.byType(AyahDivider), findsOneWidget);
  });

  testWidgets('lays Arabic out right-to-left', (WidgetTester tester) async {
    await pumpView(tester, full, LanguageMode.arabic);

    final Directionality directionality = tester.widget<Directionality>(
      find
          .ancestor(
            of: find.text('النص العربي'),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(directionality.textDirection, TextDirection.rtl);

    final Text arabic = tester.widget<Text>(find.text('النص العربي'));
    expect(arabic.textAlign, TextAlign.right);
    expect(arabic.locale, const Locale('ar'));
  });

  testWidgets('translation-only hides the Arabic and the divider',
      (WidgetTester tester) async {
    await pumpView(tester, full, LanguageMode.translation);

    expect(find.text('النص العربي'), findsNothing);
    expect(find.text('The translated line.'), findsOneWidget);
    expect(find.byType(AyahDivider), findsNothing);
  });

  testWidgets('Arabic-only hides the translation', (WidgetTester tester) async {
    await pumpView(tester, full, LanguageMode.arabic);

    expect(find.text('النص العربي'), findsOneWidget);
    expect(find.text('The translated line.'), findsNothing);
  });

  testWidgets('the transliteration is off unless asked for',
      (WidgetTester tester) async {
    await pumpView(tester, full, LanguageMode.both);
    expect(find.text('An-nass al-arabi'), findsNothing);

    await pumpView(tester, full, LanguageMode.both, showTransliteration: true);
    expect(find.text('An-nass al-arabi'), findsOneWidget);
  });

  testWidgets('a transliteration the edition lacks is simply absent',
      (WidgetTester tester) async {
    const Ayah noLatin = Ayah(
      id: 'e:1:1',
      editionId: 'e',
      ordinal: 1,
      surahNumber: 1,
      ayahNumber: 1,
      arabicText: 'النص',
      translationText: 'A translation.',
    );
    // Asking for something the source does not have must not produce an empty
    // block, and must never be filled in by the app.
    await pumpView(tester, noLatin, LanguageMode.both,
        showTransliteration: true);
    expect(find.text('A translation.'), findsOneWidget);
  });

  testWidgets('a right-to-left translation is laid out right-to-left',
      (WidgetTester tester) async {
    await pumpView(
      tester,
      full,
      LanguageMode.translation,
      translationIsRightToLeft: true,
    );

    final Directionality directionality = tester.widget<Directionality>(
      find
          .ancestor(
            of: find.text('The translated line.'),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
  });

  testWidgets('falls back to the available language when the chosen one is '
      'missing', (WidgetTester tester) async {
    const Ayah translationOnly = Ayah(
      id: 'e:1:2',
      editionId: 'e',
      ordinal: 2,
      surahNumber: 1,
      ayahNumber: 2,
      translationText: 'Only a translation exists.',
    );

    // Asking for Arabic on an entry with none still shows something readable
    // rather than a blank page.
    await pumpView(tester, translationOnly, LanguageMode.arabic);
    expect(find.text('Only a translation exists.'), findsOneWidget);
  });

  testWidgets('renders the citation, surah and juz when present',
      (WidgetTester tester) async {
    await pumpView(tester, full, LanguageMode.both);

    expect(find.text('Al-Baqarah 2:255'), findsOneWidget);
    expect(find.text('Surah: Al-Baqarah'), findsOneWidget);
    expect(find.text('Juz’ 3'), findsOneWidget);
    expect(find.text('Page 42'), findsOneWidget);
  });

  testWidgets('a sajda is noted only where the source marks one',
      (WidgetTester tester) async {
    await pumpView(tester, full, LanguageMode.both);
    expect(find.textContaining('sajdah'), findsNothing);

    const Ayah prostration = Ayah(
      id: 'e:32:15',
      editionId: 'e',
      ordinal: 3,
      surahNumber: 32,
      ayahNumber: 15,
      arabicText: 'النص',
      translationText: 'A translation.',
      sajda: true,
    );
    await pumpView(tester, prostration, LanguageMode.both);
    expect(find.textContaining('sajdah'), findsOneWidget);
  });

  testWidgets('omits the reference block when the source gives nothing',
      (WidgetTester tester) async {
    const Ayah bare = Ayah(
      id: 'e:1:3',
      editionId: 'e',
      ordinal: 3,
      surahNumber: 1,
      ayahNumber: 3,
      translationText: 'Text with no citation.',
    );
    await pumpView(tester, bare, LanguageMode.both);

    expect(find.text('REFERENCE'), findsNothing);
  });

  testWidgets('applies the reader’s text size to both scripts',
      (WidgetTester tester) async {
    await pumpView(tester, full, LanguageMode.both);
    final double baseArabic =
        tester.widget<Text>(find.text('النص العربي')).style!.fontSize!;
    final double baseTranslation = tester
        .widget<Text>(find.text('The translated line.'))
        .style!
        .fontSize!;

    await pumpView(tester, full, LanguageMode.both, scale: 1.3);
    final double largeArabic =
        tester.widget<Text>(find.text('النص العربي')).style!.fontSize!;
    final double largeTranslation = tester
        .widget<Text>(find.text('The translated line.'))
        .style!
        .fontSize!;

    expect(largeArabic, closeTo(baseArabic * 1.3, 0.01));
    expect(largeTranslation, closeTo(baseTranslation * 1.3, 0.01));
  });

  group('word by word', () {
    const Ayah glossed = Ayah(
      id: 'e:1:1',
      editionId: 'e',
      ordinal: 1,
      surahNumber: 1,
      ayahNumber: 1,
      arabicText: 'النص العربي',
      translationText: 'The translated line.',
      words: <AyahWord>[
        AyahWord(arabic: 'ٱلْحَمْدُ', translation: 'All praise'),
        AyahWord(arabic: 'لِلَّهِ', translation: '(is) for Allah'),
      ],
    );

    testWidgets('is off unless asked for', (WidgetTester tester) async {
      await pumpView(tester, glossed, LanguageMode.both);

      expect(find.text('All praise'), findsNothing);
      expect(find.text('النص العربي'), findsOneWidget);
    });

    testWidgets('replaces the running Arabic rather than repeating it',
        (WidgetTester tester) async {
      // Showing the same text twice, once whole and once in pieces, reads as a
      // mistake.
      await pumpView(tester, glossed, LanguageMode.both,
          showWordByWord: true);

      expect(find.text('ٱلْحَمْدُ'), findsOneWidget);
      expect(find.text('All praise'), findsOneWidget);
      expect(find.text('لِلَّهِ'), findsOneWidget);
      expect(find.text('(is) for Allah'), findsOneWidget);
      expect(find.text('النص العربي'), findsNothing);

      // The ayah's own translation is still there: a gloss is not a
      // substitute for it.
      expect(find.text('The translated line.'), findsOneWidget);
    });

    testWidgets('the words flow right-to-left', (WidgetTester tester) async {
      await pumpView(tester, glossed, LanguageMode.arabic,
          showWordByWord: true);

      final Directionality directionality = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.text('ٱلْحَمْدُ'),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(directionality.textDirection, TextDirection.rtl);

      // The first word sits to the right of the second.
      final double first = tester.getCenter(find.text('ٱلْحَمْدُ')).dx;
      final double second = tester.getCenter(find.text('لِلَّهِ')).dx;
      expect(first, greaterThan(second));
    });

    testWidgets('an ayah with no glosses keeps its running Arabic',
        (WidgetTester tester) async {
      // Asking for something the installed edition does not have must never
      // blank the Arabic out.
      await pumpView(tester, full, LanguageMode.both, showWordByWord: true);

      expect(find.text('النص العربي'), findsOneWidget);
    });
  });

  testWidgets('never offers to speak the Arabic aloud',
      (WidgetTester tester) async {
    // Recitation is not a text-to-speech job. The only listen control the view
    // can show is for the translation, and it is only there when a screen
    // passes one in.
    await pumpView(tester, full, LanguageMode.arabic);
    expect(find.byTooltip('Listen to the Arabic'), findsNothing);
    expect(find.byTooltip('Listen to the translation'), findsNothing);
  });
}
