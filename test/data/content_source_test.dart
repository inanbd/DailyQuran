import 'dart:convert';

import 'package:daily_quran/core/errors/app_exception.dart';
import 'package:daily_quran/data/content/asset_quran_content_source.dart';
import 'package:daily_quran/data/content/content_schema.dart';
import 'package:daily_quran/domain/entities/ayah.dart';
import 'package:daily_quran/domain/entities/ayah_word.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/entities/quran_edition.dart';
import 'package:daily_quran/domain/entities/surah.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String catalog(List<Map<String, Object?>> editions) => jsonEncode(
        <String, Object?>{'schemaVersion': 1, 'editions': editions},
      );

  const Map<String, Object?> saheeh = <String, Object?>{
    'id': 'saheeh_international',
    'slug': 'saheeh_international',
    'titleEnglish': 'Saheeh International',
    'titleArabic': 'القرآن الكريم',
    'translator': 'Umm Muhammad',
    'description': 'An English translation.',
    'languageName': 'English',
    'languageCode': 'en-US',
    'totalAyah': 3,
    'progressScope': 'quran',
    'verification': 'verified',
    'source': <String, Object?>{
      'name': 'Example dataset',
      'url': 'https://example.org/dataset',
      'translator': 'Example translator',
      'licence': 'CC BY-SA 4.0',
      'retrievedAt': '2026-02-01T00:00:00Z',
    },
  };

  String editionFile() => jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'editionId': 'saheeh_international',
        'ayat': <Object?>[
          <String, Object?>{
            'surah': 1,
            'ayah': 1,
            'surahNameEnglish': 'Al-Fatihah',
            'arabic': 'النص العربي الأول',
            'translation': 'The first translated line.',
            'transliteration': 'An-nass al-arabi al-awwal',
            'juz': 1,
            'page': 1,
            'reference': 'Al-Fatihah 1:1',
          },
          <String, Object?>{
            'surah': 1,
            'ayah': 2,
            'arabic': '   ',
            'translation': 'Only a translation here.',
          },
          <String, Object?>{
            'surah': 32,
            'ayah': 15,
            'arabic': 'النص العربي الثالث',
            'sajda': true,
          },
        ],
      });

  String surahIndex() => jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'surahs': <Object?>[
          <String, Object?>{
            'number': 1,
            'nameArabic': 'الفاتحة',
            'nameTransliterated': 'Al-Fatihah',
            'nameEnglish': 'The Opener',
            'ayahCount': 7,
            'revelationPlace': 'meccan',
          },
          <String, Object?>{
            'number': 32,
            'nameArabic': 'السجدة',
            'nameTransliterated': 'As-Sajdah',
            'nameEnglish': 'The Prostration',
            'ayahCount': 30,
            'revelationPlace': 'meccan',
          },
        ],
      });

  String wordIndex() => jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'languageName': 'English',
        'source': <String, Object?>{'name': 'Example word source'},
        'words': <String, Object?>{
          '1:1': <Object?>[
            <String, Object?>{'arabic': 'بِسْمِ', 'translation': 'In (the) name'},
            <String, Object?>{'arabic': 'ٱللَّهِ', 'translation': '(of) Allah'},
          ],
        },
      });

  AssetQuranContentSource sourceWith(Map<String, String> assets) =>
      AssetQuranContentSource(bundle: MapAssetBundle(assets));

  test('parses the catalog including source attribution', () async {
    final AssetQuranContentSource source = sourceWith(<String, String>{
      ContentSchema.catalogAsset: catalog(<Map<String, Object?>>[saheeh]),
    });

    final List<QuranEdition> editions = await source.loadCatalog();
    expect(editions, hasLength(1));

    final QuranEdition edition = editions.single;
    expect(edition.id, 'saheeh_international');
    expect(edition.titleArabic, 'القرآن الكريم');
    expect(edition.totalAyah, 3);
    expect(edition.languageCode, 'en-US');
    expect(edition.verification, ContentVerification.verified);
    expect(edition.source.name, 'Example dataset');
    expect(edition.source.translator, 'Example translator');
    expect(edition.source.licence, 'CC BY-SA 4.0');
    expect(edition.source.retrievedAt, isNotNull);
  });

  test('a declared scope is shared; an undeclared one stands alone', () async {
    final AssetQuranContentSource source = sourceWith(<String, String>{
      ContentSchema.catalogAsset: catalog(<Map<String, Object?>>[
        saheeh,
        <String, Object?>{
          ...saheeh,
          'id': 'pickthall',
          'slug': 'pickthall',
        },
        <String, Object?>{
          ...saheeh,
          'id': 'dev_sample',
          'slug': 'dev_sample',
          'verification': 'development_fixture',
        }..remove('progressScope'),
      ]),
    });

    final List<QuranEdition> editions = await source.loadCatalog();
    expect(editions[0].scope, 'quran');
    expect(editions[1].scope, 'quran', reason: 'translations share a place');
    expect(editions[2].scope, 'dev_sample', reason: 'the fixture stands alone');
  });

  test('a right-to-left translation is declared as such', () async {
    final AssetQuranContentSource source = sourceWith(<String, String>{
      ContentSchema.catalogAsset: catalog(<Map<String, Object?>>[
        saheeh,
        <String, Object?>{
          ...saheeh,
          'id': 'maududi',
          'slug': 'maududi',
          'languageDirection': 'rtl',
        },
      ]),
    });

    final List<QuranEdition> editions = await source.loadCatalog();
    expect(editions[0].isRightToLeft, isFalse);
    expect(editions[1].isRightToLeft, isTrue);
  });

  test('marks fixture editions as unverified', () async {
    final AssetQuranContentSource source = sourceWith(<String, String>{
      ContentSchema.catalogAsset: catalog(<Map<String, Object?>>[
        <String, Object?>{...saheeh, 'verification': 'development_fixture'},
      ]),
    });
    final QuranEdition edition = (await source.loadCatalog()).single;
    expect(edition.isFixture, isTrue);
  });

  test('loads ayat with contiguous ordinals and verbatim text', () async {
    final AssetQuranContentSource source = sourceWith(<String, String>{
      ContentSchema.catalogAsset: catalog(<Map<String, Object?>>[saheeh]),
      ContentSchema.assetForSlug('saheeh_international'): editionFile(),
    });

    final List<Ayah> ayat = await source.loadAyat('saheeh_international');
    expect(ayat.map((Ayah a) => a.ordinal), <int>[1, 2, 3]);
    expect(ayat.first.arabicText, 'النص العربي الأول');
    expect(ayat.first.translationText, 'The first translated line.');
    expect(ayat.first.transliteration, 'An-nass al-arabi al-awwal');
    expect(ayat.first.juz, 1);
    expect(ayat.first.verseKey, '1:1');

    // Whitespace-only fields become null so the reader never sees a blank block.
    expect(ayat[1].hasArabic, isFalse);
    expect(ayat[1].hasTranslation, isTrue);

    // The reading position is the array order; the verse key is what the
    // source published.
    expect(ayat[2].verseKey, '32:15');
    expect(ayat[2].ordinal, 3);
    expect(ayat[2].hasTranslation, isFalse);
  });

  test('a sajda is recorded only where the source marks one', () async {
    final AssetQuranContentSource source = sourceWith(<String, String>{
      ContentSchema.catalogAsset: catalog(<Map<String, Object?>>[saheeh]),
      ContentSchema.assetForSlug('saheeh_international'): editionFile(),
    });
    final List<Ayah> ayat = await source.loadAyat('saheeh_international');
    expect(ayat[0].sajda, isFalse);
    expect(ayat[2].sajda, isTrue);
  });

  test('falls back to the edition source for per-ayah attribution', () async {
    final AssetQuranContentSource source = sourceWith(<String, String>{
      ContentSchema.catalogAsset: catalog(<Map<String, Object?>>[saheeh]),
      ContentSchema.assetForSlug('saheeh_international'): editionFile(),
    });
    final List<Ayah> ayat = await source.loadAyat('saheeh_international');
    expect(ayat.first.source, 'Example dataset');
  });

  test('an edition inherits the shared surah index', () async {
    final AssetQuranContentSource source = sourceWith(<String, String>{
      ContentSchema.catalogAsset: catalog(<Map<String, Object?>>[saheeh]),
      ContentSchema.assetForSlug('saheeh_international'): editionFile(),
      ContentSchema.surahIndexAsset: surahIndex(),
    });

    final List<Surah> surahs = await source.loadSurahs('saheeh_international');
    expect(surahs, hasLength(2));
    expect(surahs.first.nameTransliterated, 'Al-Fatihah');
    expect(surahs.first.ayahCount, 7);
    expect(surahs.first.revelationPlace, RevelationPlace.meccan);
  });

  test('an edition that carries its own surahs uses those instead', () async {
    // The development fixture's sections are not the Qur'an's, so it must not
    // borrow real surah names for them.
    final String own = jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'editionId': 'saheeh_international',
      'surahs': <Object?>[
        <String, Object?>{
          'number': 1,
          'nameEnglish': 'Layout checks',
          'ayahCount': 3,
        },
      ],
      'ayat': <Object?>[
        <String, Object?>{'surah': 1, 'ayah': 1, 'arabic': 'نص'},
      ],
    });
    final AssetQuranContentSource source = sourceWith(<String, String>{
      ContentSchema.catalogAsset: catalog(<Map<String, Object?>>[saheeh]),
      ContentSchema.assetForSlug('saheeh_international'): own,
      ContentSchema.surahIndexAsset: surahIndex(),
    });

    final List<Surah> surahs = await source.loadSurahs('saheeh_international');
    expect(surahs, hasLength(1));
    expect(surahs.single.nameEnglish, 'Layout checks');
  });

  test('the shared word index is attached to every ayah that has one',
      () async {
    final AssetQuranContentSource source = sourceWith(<String, String>{
      ContentSchema.catalogAsset: catalog(<Map<String, Object?>>[saheeh]),
      ContentSchema.assetForSlug('saheeh_international'): editionFile(),
      ContentSchema.wordByWordAsset: wordIndex(),
    });

    final List<Ayah> ayat = await source.loadAyat('saheeh_international');
    expect(ayat.first.hasWords, isTrue);
    expect(ayat.first.words, hasLength(2));
    expect(ayat.first.words.first.arabic, 'بِسْمِ');
    expect(ayat.first.words.first.translation, 'In (the) name');

    // Ayat the index does not cover simply have none.
    expect(ayat[1].hasWords, isFalse);
    expect(ayat[2].hasWords, isFalse);
  });

  test('a missing word index costs the glosses and nothing else', () async {
    final AssetQuranContentSource source = sourceWith(<String, String>{
      ContentSchema.catalogAsset: catalog(<Map<String, Object?>>[saheeh]),
      ContentSchema.assetForSlug('saheeh_international'): editionFile(),
    });

    final List<Ayah> ayat = await source.loadAyat('saheeh_international');
    expect(ayat, hasLength(3));
    expect(ayat.first.hasWords, isFalse);
    expect(ayat.first.arabicText, 'النص العربي الأول');
  });

  test('an edition that carries its own words keeps them', () async {
    final String own = jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'editionId': 'saheeh_international',
      'ayat': <Object?>[
        <String, Object?>{
          'surah': 1,
          'ayah': 1,
          'arabic': 'النص',
          'words': <Object?>[
            <String, Object?>{'arabic': 'خاص', 'translation': 'its own'},
          ],
        },
      ],
    });
    final AssetQuranContentSource source = sourceWith(<String, String>{
      ContentSchema.catalogAsset: catalog(<Map<String, Object?>>[saheeh]),
      ContentSchema.assetForSlug('saheeh_international'): own,
      ContentSchema.wordByWordAsset: wordIndex(),
    });

    final List<Ayah> ayat = await source.loadAyat('saheeh_international');
    expect(ayat.single.words, hasLength(1));
    expect(ayat.single.words.single.translation, 'its own');
  });

  test('a malformed word entry is dropped, not fatal', () async {
    final String broken = jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'words': <String, Object?>{
        '1:1': <Object?>[
          'not an object',
          <String, Object?>{'arabic': '   ', 'translation': '   '},
          <String, Object?>{'arabic': 'صحيح', 'translation': 'sound'},
        ],
      },
    });
    final AssetQuranContentSource source = sourceWith(<String, String>{
      ContentSchema.catalogAsset: catalog(<Map<String, Object?>>[saheeh]),
      ContentSchema.assetForSlug('saheeh_international'): editionFile(),
      ContentSchema.wordByWordAsset: broken,
    });

    final List<Ayah> ayat = await source.loadAyat('saheeh_international');
    expect(ayat.first.words, hasLength(1));
    expect(ayat.first.words.single, const AyahWord(
      arabic: 'صحيح',
      translation: 'sound',
    ));
  });

  test('reports content as unavailable rather than throwing', () async {
    final AssetQuranContentSource source = sourceWith(<String, String>{
      ContentSchema.catalogAsset: catalog(<Map<String, Object?>>[saheeh]),
    });
    expect(await source.hasContentFor('saheeh_international'), isFalse);
    expect(await source.hasContentFor('nonexistent'), isFalse);
    expect(await source.loadSurahs('nonexistent'), isEmpty);
  });

  test('a missing catalog is a catalog failure, not a crash', () async {
    final AssetQuranContentSource source = sourceWith(<String, String>{});
    expect(
      () => source.loadCatalog(),
      throwsA(isA<CatalogUnavailableException>()),
    );
  });

  test('malformed catalog JSON is reported cleanly', () async {
    final AssetQuranContentSource source = sourceWith(<String, String>{
      ContentSchema.catalogAsset: '{not json',
    });
    expect(
      () => source.loadCatalog(),
      throwsA(isA<CatalogUnavailableException>()),
    );
  });

  test('an unknown edition cannot be loaded', () async {
    final AssetQuranContentSource source = sourceWith(<String, String>{
      ContentSchema.catalogAsset: catalog(<Map<String, Object?>>[saheeh]),
    });
    expect(
      () => source.loadAyat('nonexistent'),
      throwsA(isA<DatasetUnavailableException>()),
    );
  });
}
