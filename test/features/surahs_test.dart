import 'package:daily_quran/domain/entities/ayah.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/entities/surah.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// The surah index is a way to jump around the mushaf, and it stays behind an
/// icon: the app is built around reading in order, and a table of contents on
/// the reading surface would invite skimming.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object> onboarded() => <String, Object>{
        'flutter.pref.onboarding_complete': true,
        'flutter.pref.current_edition_id': 'test_edition',
        'flutter.notify.enabled': true,
        'flutter.notify.frequency': NotificationFrequency.daily.storageKey,
        'flutter.notify.time': '08:00',
      };

  /// Ten ayat split into two named surahs: 1–5 and 6–10.
  FakeContentSource withSurahs() {
    final FakeContentSource base = FakeContentSource.single(count: 10);
    return FakeContentSource(
      editions: base.editions,
      ayatByEdition: base.ayatByEdition,
      surahsByEdition: <String, List<Surah>>{
        'test_edition': const <Surah>[
          Surah(
            editionId: 'test_edition',
            number: 1,
            nameArabic: 'الفاتحة',
            nameTransliterated: 'Al-Fatihah',
            nameEnglish: 'The Opener',
            ayahCount: 5,
            revelationPlace: RevelationPlace.meccan,
          ),
          Surah(
            editionId: 'test_edition',
            number: 2,
            nameArabic: 'البقرة',
            nameTransliterated: 'Al-Baqarah',
            nameEnglish: 'The Cow',
            ayahCount: 5,
            revelationPlace: RevelationPlace.medinan,
          ),
        ],
      },
    );
  }

  testWidgets('an edition with no surah data offers no surahs control',
      (WidgetTester tester) async {
    final FakeContentSource base = FakeContentSource.single(count: 10);
    final TestHarness harness = await TestHarness.create(
      contentSource: FakeContentSource(
        editions: base.editions,
        ayatByEdition: base.ayatByEdition,
      ),
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    expect(find.byTooltip('Surahs'), findsNothing);
  });

  testWidgets('surahs stay behind an icon rather than on the page',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: withSurahs(),
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    // Offered, but not shown: the reading surface is unchanged.
    expect(find.byTooltip('Surahs'), findsOneWidget);
    expect(find.textContaining('Al-Baqarah · The Cow'), findsNothing);
  });

  testWidgets('opening a surah moves the reader to its first ayah',
      (WidgetTester tester) async {
    final TestHarness harness = await TestHarness.create(
      contentSource: withSurahs(),
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    expect(find.text('Translation number 1.'), findsOneWidget);

    await tester.tap(find.byTooltip('Surahs'));
    await harness.settle(tester);
    expect(find.text('Al-Fatihah · The Opener'), findsOneWidget);
    expect(find.text('Al-Baqarah · The Cow'), findsOneWidget);
    // The index says what kind of surah each one is, and how long.
    expect(find.text('Meccan · 5 ayat'), findsOneWidget);
    expect(find.text('Medinan · 5 ayat'), findsOneWidget);

    await tester.tap(find.text('Al-Baqarah · The Cow'));
    await harness.settle(tester);

    // The sheet closes and the reader is at the start of that surah.
    expect(find.text('Al-Baqarah · The Cow'), findsNothing);
    expect(find.text('Translation number 6.'), findsOneWidget);
    // Jumping is browsing, not reading: nothing was marked on the way.
    expect(find.text('0 of 10 read'), findsOneWidget);
  });

  testWidgets('a surah with nothing stored against it does not move the reader',
      (WidgetTester tester) async {
    // Surah metadata and ayah rows are imported separately, so an index entry
    // can legitimately point at nothing.
    final FakeContentSource base = FakeContentSource.single(count: 5);
    final TestHarness harness = await TestHarness.create(
      contentSource: FakeContentSource(
        editions: base.editions,
        ayatByEdition: <String, List<Ayah>>{...base.ayatByEdition},
        surahsByEdition: <String, List<Surah>>{
          'test_edition': const <Surah>[
            Surah(
              editionId: 'test_edition',
              number: 99,
              nameArabic: 'غير موجودة',
              nameTransliterated: 'Missing',
              nameEnglish: 'Not imported',
              ayahCount: 0,
            ),
          ],
        },
      ),
      initialPreferences: onboarded(),
    );
    await harness.pumpApp(tester);

    await tester.tap(find.byTooltip('Surahs'));
    await harness.settle(tester);
    await tester.tap(find.text('Missing · Not imported'));
    await harness.settle(tester);

    // The sheet stays open and the reader has not been moved: the row is
    // inert rather than sending them somewhere arbitrary.
    expect(find.text('Missing · Not imported'), findsOneWidget);
    expect(find.text('Translation number 1.'), findsOneWidget);
    expect(find.text('0 of 5 read'), findsOneWidget);
  });
}
