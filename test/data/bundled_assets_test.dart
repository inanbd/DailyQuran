import 'dart:convert';

import 'package:daily_quran/data/content/asset_quran_content_source.dart';
import 'package:daily_quran/data/content/content_schema.dart';
import 'package:daily_quran/domain/entities/ayah.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/entities/quran_edition.dart';
import 'package:daily_quran/domain/entities/surah.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the JSON that actually ships with the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AssetQuranContentSource source;

  setUp(() => source = AssetQuranContentSource());

  test('the bundled catalog parses', () async {
    final List<QuranEdition> editions = await source.loadCatalog();
    expect(editions, isNotEmpty);

    for (final QuranEdition edition in editions) {
      expect(edition.id, isNotEmpty);
      expect(edition.slug, isNotEmpty);
      expect(edition.titleEnglish, isNotEmpty);
      expect(edition.totalAyah, greaterThan(0));
      expect(edition.languageCode, isNotEmpty);
      expect(edition.source.name, isNotEmpty);
    }

    final Set<String> ids = editions.map((QuranEdition e) => e.id).toSet();
    expect(ids.length, editions.length, reason: 'ids must be unique');
  });

  test('at least one edition ships with readable content', () async {
    final List<QuranEdition> editions = await source.loadCatalog();
    final List<QuranEdition> available = <QuranEdition>[
      for (final QuranEdition edition in editions)
        if (await source.hasContentFor(edition.id)) edition,
    ];
    expect(
      available,
      isNotEmpty,
      reason: 'the app must be runnable straight after checkout',
    );
  });

  test('the development sample is labelled a fixture', () async {
    final List<QuranEdition> editions = await source.loadCatalog();
    final QuranEdition sample = editions.firstWhere(
      (QuranEdition edition) => edition.id == 'dev_sample',
    );
    expect(sample.verification, ContentVerification.developmentFixture);
    expect(sample.isFixture, isTrue);
  });

  test('the fixture keeps its own progress scope', () async {
    // Placeholder progress must never be able to appear as progress through
    // the Qur'an.
    final List<QuranEdition> editions = await source.loadCatalog();
    final QuranEdition sample = editions.firstWhere(
      (QuranEdition edition) => edition.id == 'dev_sample',
    );
    expect(sample.scope, 'dev_sample');
    expect(sample.scope, isNot('quran'));
  });

  test('every verified edition shares one reading scope', () async {
    // Ayah 2:255 is the same ayah whichever translation renders it, so a
    // reader who changes translation must keep their place.
    final List<QuranEdition> editions = await source.loadCatalog();
    final Iterable<QuranEdition> verified =
        editions.where((QuranEdition e) => !e.isFixture);
    expect(verified, isNotEmpty);
    for (final QuranEdition edition in verified) {
      expect(
        edition.scope,
        'quran',
        reason: '${edition.id} must share the Qur’an reading scope',
      );
    }
  });

  test('any readable edition is a fixture or carries real attribution',
      () async {
    // The invariant that matters: text is never shown without the reader being
    // able to tell where it came from, or that it is placeholder data.
    final List<QuranEdition> editions = await source.loadCatalog();
    for (final QuranEdition edition in editions) {
      if (!await source.hasContentFor(edition.id)) continue;
      if (edition.isFixture) continue;

      expect(
        edition.verification,
        ContentVerification.verified,
        reason: '${edition.id} must be verified or marked a fixture',
      );
      expect(
        edition.source.name,
        isNot('Not yet imported'),
        reason: '${edition.id} ships text, so it needs real attribution',
      );
      expect(edition.source.name.trim(), isNotEmpty);
    }
  });

  test('the development fixture loads with contiguous ordinals', () async {
    final List<Ayah> ayat = await source.loadAyat('dev_sample');
    expect(ayat, isNotEmpty);
    for (int i = 0; i < ayat.length; i++) {
      expect(ayat[i].ordinal, i + 1);
      expect(ayat[i].hasAnyText, isTrue);
    }

    // Verse keys must be unique, or progress rows would collide.
    final Set<String> keys = ayat.map((Ayah a) => a.verseKey).toSet();
    expect(keys.length, ayat.length);
  });

  test('the fixture carries its own sections rather than real surah names',
      () async {
    final List<Surah> surahs = await source.loadSurahs('dev_sample');
    expect(surahs, isNotEmpty);
    for (final Surah surah in surahs) {
      expect(
        surah.nameEnglish,
        isNot('The Opener'),
        reason: 'the fixture must not borrow real surah names',
      );
    }
  });

  test('every readable edition has unique, contiguous ordinals', () async {
    final List<QuranEdition> editions = await source.loadCatalog();
    for (final QuranEdition edition in editions) {
      if (!await source.hasContentFor(edition.id)) continue;

      final List<Ayah> ayat = await source.loadAyat(edition.id);
      expect(ayat, isNotEmpty, reason: edition.id);
      expect(
        ayat.map((Ayah a) => a.verseKey).toSet().length,
        ayat.length,
        reason: '${edition.id} has duplicate verse keys',
      );
      for (int i = 0; i < ayat.length; i++) {
        expect(ayat[i].ordinal, i + 1, reason: edition.id);
        expect(
          ayat[i].hasAnyText,
          isTrue,
          reason: '${edition.id} ordinal ${i + 1} has no text',
        );
      }
    }
  });

  test('the bundled surah index is the whole Qur’an', () async {
    // 114 surahs summing to 6,236 ayat in the standard Kufan numbering. A typo
    // in a single ayah count breaks this sum, which is the point.
    final String raw =
        await rootBundle.loadString(ContentSchema.surahIndexAsset);
    final Map<String, Object?> json =
        jsonDecode(raw) as Map<String, Object?>;
    final List<Object?> surahs = json['surahs']! as List<Object?>;

    expect(surahs, hasLength(114));

    int total = 0;
    for (int i = 0; i < surahs.length; i++) {
      final Map<String, Object?> surah = surahs[i] as Map<String, Object?>;
      expect(surah['number'], i + 1);
      expect(surah['nameArabic'], isNotEmpty);
      expect(surah['nameTransliterated'], isNotEmpty);
      expect(surah['nameEnglish'], isNotEmpty);
      final int count = surah['ayahCount']! as int;
      expect(count, greaterThan(0));
      total += count;
      expect(
        RevelationPlace.fromStorage(surah['revelationPlace'] as String?),
        isNot(RevelationPlace.unknown),
        reason: 'surah ${i + 1} must be classified',
      );
    }
    expect(total, 6236);
    expect(json['totalAyah'], 6236);
  });

  test('a complete edition matches the surah index', () async {
    // Any edition claiming the standard numbering must actually line up with
    // it, surah by surah — an off-by-one in an import shows up here.
    final List<QuranEdition> editions = await source.loadCatalog();
    final String raw =
        await rootBundle.loadString(ContentSchema.surahIndexAsset);
    final List<Object?> index =
        (jsonDecode(raw) as Map<String, Object?>)['surahs']! as List<Object?>;
    final Map<int, int> expected = <int, int>{
      for (final Object? entry in index)
        (entry! as Map<String, Object?>)['number']! as int:
            (entry as Map<String, Object?>)['ayahCount']! as int,
    };

    for (final QuranEdition edition in editions) {
      if (edition.isFixture) continue;
      if (!await source.hasContentFor(edition.id)) continue;

      final List<Ayah> ayat = await source.loadAyat(edition.id);
      if (ayat.length != 6236) continue; // A different numbering; not ours.

      final Map<int, int> actual = <int, int>{};
      for (final Ayah ayah in ayat) {
        actual[ayah.surahNumber] = (actual[ayah.surahNumber] ?? 0) + 1;
      }
      expect(actual, expected, reason: '${edition.id} does not match the index');
    }
  });
}
