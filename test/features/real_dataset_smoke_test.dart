import 'package:daily_quran/data/content/asset_quran_content_source.dart';
import 'package:daily_quran/domain/entities/ayah.dart';
import 'package:daily_quran/domain/entities/quran_edition.dart';
import 'package:daily_quran/domain/entities/surah.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads an imported edition through the real content source.
///
/// Skipped when the edition has not been imported, so a checkout carrying only
/// the development fixture stays green.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String editionId = 'saheeh_international';

  test('an imported edition reads end to end', () async {
    final AssetQuranContentSource source = AssetQuranContentSource();
    if (!await source.hasContentFor(editionId)) {
      markTestSkipped('$editionId not imported');
      return;
    }

    final List<QuranEdition> catalog = await source.loadCatalog();
    final QuranEdition edition =
        catalog.firstWhere((QuranEdition e) => e.id == editionId);
    expect(edition.titleArabic, 'القرآن الكريم');
    expect(edition.totalAyah, 6236);
    expect(edition.scope, 'quran');
    expect(edition.source.name, isNot('Not yet imported'));
    expect(edition.source.licence, isNotNull);

    final List<Ayah> ayat = await source.loadAyat(editionId);
    expect(ayat, hasLength(6236));

    // The first ayah of the mushaf.
    final Ayah first = ayat.first;
    expect(first.ordinal, 1);
    expect(first.verseKey, '1:1');
    expect(first.surahNameEnglish, 'Al-Fatihah');
    expect(first.hasArabic, isTrue);

    // Ayat al-Kursi is the 262nd ayah in mushaf order: 7 in Al-Fatihah plus
    // 255 in Al-Baqarah. Getting this wrong means the ordering is wrong.
    final Ayah kursi = ayat[261];
    expect(kursi.verseKey, '2:255');
    expect(kursi.surahNumber, 2);
    expect(kursi.ayahNumber, 255);
    expect(kursi.reference, 'Al-Baqarah 2:255');
    expect(kursi.hasArabic, isTrue);

    // The last ayah of the mushaf.
    final Ayah last = ayat.last;
    expect(last.ordinal, 6236);
    expect(last.verseKey, '114:6');

    // Spot-check the start, middle and end, as the import checklist advises.
    for (final int index in <int>[0, 3117, 6235]) {
      expect(ayat[index].hasArabic, isTrue, reason: 'ayah ${index + 1}');
    }

    // A complete edition inherits the bundled surah index rather than
    // duplicating it.
    final List<Surah> surahs = await source.loadSurahs(editionId);
    expect(surahs, hasLength(114));
    expect(surahs.last.nameTransliterated, 'An-Nas');
  });
}
