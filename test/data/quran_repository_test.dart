import 'package:daily_quran/core/errors/app_exception.dart';
import 'package:daily_quran/data/local/app_database.dart';
import 'package:daily_quran/data/local/ayah_dao.dart';
import 'package:daily_quran/data/repositories/quran_repository_impl.dart';
import 'package:daily_quran/domain/entities/ayah.dart';
import 'package:daily_quran/domain/entities/quran_edition.dart';
import 'package:daily_quran/domain/entities/surah.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase database;
  late QuranRepositoryImpl repository;
  late FakeContentSource content;

  setUp(() {
    database = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: inMemoryDatabasePath,
    );
    content = FakeContentSource.single(id: 'edition', count: 10);
    repository = QuranRepositoryImpl(
      contentSource: content,
      dao: AyahDao(database),
    );
  });

  tearDown(() => database.close());

  test('editions start uninstalled but available', () async {
    final List<QuranEdition> editions = await repository.editions();
    expect(editions, hasLength(1));
    expect(editions.single.isInstalled, isFalse);
    expect(editions.single.isAvailable, isTrue);
    expect(editions.single.isReadable, isTrue);
  });

  test('installing copies the text into local storage', () async {
    final QuranEdition installed = await repository.installEdition('edition');

    expect(installed.isInstalled, isTrue);
    expect(installed.totalAyah, 10);
    expect(await repository.installedCount('edition'), 10);

    final Ayah? first = await repository.ayahAt('edition', 1);
    expect(first?.translationText, 'Translation number 1.');
    expect(first?.arabicText, 'نص عربي رقم 1');
    expect(first?.verseKey, '1:1');
  });

  test('installing twice does not re-read the source', () async {
    await repository.installEdition('edition');
    expect(content.loadAyatCalls, 1);

    await repository.installEdition('edition');
    expect(content.loadAyatCalls, 1, reason: 'already installed');

    await repository.installEdition('edition', force: true);
    expect(content.loadAyatCalls, 2, reason: 'forced re-import');
    expect(await repository.installedCount('edition'), 10);
  });

  test('reads are served from storage, so the source is not needed again',
      () async {
    await repository.installEdition('edition');
    final int callsAfterInstall = content.loadAyatCalls;

    for (int ordinal = 1; ordinal <= 10; ordinal++) {
      expect((await repository.ayahAt('edition', ordinal))?.ordinal, ordinal);
    }
    expect(content.loadAyatCalls, callsAfterInstall);
  });

  test('an ayah can be found by its verse key', () async {
    await repository.installEdition('edition');

    final Ayah? ayah = await repository.ayahByVerseKey('edition', '2:3');
    expect(ayah, isNotNull);
    expect(ayah!.surahNumber, 2);
    expect(ayah.ayahNumber, 3);
    // Two surahs of five: 2:3 is the eighth ayah.
    expect(ayah.ordinal, 8);

    expect(await repository.ayahByVerseKey('edition', '99:1'), isNull);
  });

  test('surahs are stored and the first ordinal of one is navigable', () async {
    await repository.installEdition('edition');

    final List<Surah> surahs = await repository.surahs('edition');
    expect(surahs.map((Surah s) => s.number), <int>[1, 2]);
    expect(surahs.first.ayahCount, 5);

    expect(await repository.firstOrdinalOfSurah('edition', 1), 1);
    expect(await repository.firstOrdinalOfSurah('edition', 2), 6);
    // A surah with nothing stored against it is not navigable, not an error.
    expect(await repository.firstOrdinalOfSurah('edition', 99), isNull);
  });

  test('out-of-range positions return null rather than throwing', () async {
    await repository.installEdition('edition');
    expect(await repository.ayahAt('edition', 0), isNull);
    expect(await repository.ayahAt('edition', -1), isNull);
    expect(await repository.ayahAt('edition', 11), isNull);
  });

  test('an edition missing from the catalog cannot be installed', () async {
    expect(
      () => repository.installEdition('nope'),
      throwsA(isA<DatasetUnavailableException>()),
    );
  });

  test('the stored count wins over the catalog total', () async {
    // The catalog claims 10; storage is what progress is actually measured
    // against.
    await repository.installEdition('edition');
    final QuranEdition? edition = await repository.edition('edition');
    expect(edition?.totalAyah, 10);
    expect(edition?.isInstalled, isTrue);
  });

  test('a catalog entry with no content is listed but not readable', () async {
    final FakeContentSource catalogOnly = FakeContentSource(
      editions: content.editions,
      ayatByEdition: const <String, List<Ayah>>{},
    );
    final QuranRepositoryImpl repo = QuranRepositoryImpl(
      contentSource: catalogOnly,
      dao: AyahDao(database),
    );

    final List<QuranEdition> editions = await repo.editions();
    expect(editions.single.isAvailable, isFalse);
    expect(editions.single.isReadable, isFalse);
  });
}
