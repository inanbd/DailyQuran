import 'dart:io';

import 'package:daily_quran/data/local/app_database.dart';
import 'package:daily_quran/data/local/ayah_dao.dart';
import 'package:daily_quran/data/local/favourites_dao.dart';
import 'package:daily_quran/data/local/progress_dao.dart';
import 'package:daily_quran/domain/entities/ayah.dart';
import 'package:daily_quran/domain/entities/ayah_word.dart';
import 'package:daily_quran/domain/entities/reading_progress.dart';
import 'package:daily_quran/domain/entities/surah.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The v1 schema, copied verbatim from the shipped v1 so the upgrade is
/// exercised against what readers actually have. The only difference from v2 is
/// that `ayah` has no `words` column.
const String _v1Ayah = '''
  CREATE TABLE ayah (
    id TEXT PRIMARY KEY,
    edition_id TEXT NOT NULL,
    ordinal INTEGER NOT NULL,
    surah_number INTEGER NOT NULL,
    ayah_number INTEGER NOT NULL,
    verse_key TEXT NOT NULL,
    surah_name_arabic TEXT,
    surah_name_english TEXT,
    arabic_text TEXT,
    translation_text TEXT,
    transliteration TEXT,
    juz INTEGER,
    page INTEGER,
    sajda INTEGER NOT NULL DEFAULT 0,
    reference TEXT,
    source TEXT
  )
''';

const String _v1Progress = '''
  CREATE TABLE reading_progress (
    scope TEXT PRIMARY KEY,
    current_ordinal INTEGER NOT NULL DEFAULT 1,
    started_at INTEGER,
    last_read_at INTEGER,
    completed_at INTEGER
  )
''';

const String _v1Read = '''
  CREATE TABLE read_ayah (
    scope TEXT NOT NULL,
    verse_key TEXT NOT NULL,
    ordinal INTEGER NOT NULL,
    read_at INTEGER NOT NULL,
    PRIMARY KEY (scope, verse_key)
  )
''';

const String _v1Favourites = '''
  CREATE TABLE favourite_ayah (
    scope TEXT NOT NULL,
    verse_key TEXT NOT NULL,
    ordinal INTEGER NOT NULL,
    saved_at INTEGER NOT NULL,
    PRIMARY KEY (scope, verse_key)
  )
''';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late String path;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('daily_quran_migration');
    path = p.join(directory.path, AppDatabase.fileName);
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  /// Writes a v1 database carrying a reader's progress and a saved ayah.
  Future<void> seedV1() async {
    final Database db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute(_v1Ayah);
          await db.execute(_v1Progress);
          await db.execute(_v1Read);
          await db.execute(_v1Favourites);
        },
      ),
    );
    await db.insert('ayah', <String, Object?>{
      'id': 'saheeh_international:2:255',
      'edition_id': 'saheeh_international',
      'ordinal': 262,
      'surah_number': 2,
      'ayah_number': 255,
      'verse_key': '2:255',
      'arabic_text': 'نص',
      'translation_text': 'A translation.',
    });
    await db.insert('reading_progress', <String, Object?>{
      'scope': 'quran',
      'current_ordinal': 262,
      'started_at': 1700000000000,
      'last_read_at': 1700000900000,
    });
    await db.insert('read_ayah', <String, Object?>{
      'scope': 'quran',
      'verse_key': '2:255',
      'ordinal': 262,
      'read_at': 1700000000000,
    });
    await db.insert('favourite_ayah', <String, Object?>{
      'scope': 'quran',
      'verse_key': '2:255',
      'ordinal': 262,
      'saved_at': 1700000000000,
    });
    await db.close();
  }

  test('upgrading from v1 keeps reading progress and favourites', () async {
    await seedV1();

    final AppDatabase upgraded = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: path,
    );
    addTearDown(upgraded.close);
    final Database db = await upgraded.database;

    expect(await db.getVersion(), AppDatabase.schemaVersion);

    final ReadingProgress progress =
        await ProgressDao(upgraded).progressFor('quran', 6236);
    expect(progress.currentOrdinal, 262);
    expect(progress.totalRead, 1);
    expect(progress.startedAt, isNotNull);

    expect(
      await FavouritesDao(upgraded).isFavourite('quran', '2:255'),
      isTrue,
    );
  });

  test('upgrading from v1 adds the words column', () async {
    await seedV1();

    final AppDatabase upgraded = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: path,
    );
    addTearDown(upgraded.close);
    final Database db = await upgraded.database;

    final List<Map<String, Object?>> columns =
        await db.rawQuery('PRAGMA table_info(${AppDatabase.ayahTable})');
    expect(
      columns.map((Map<String, Object?> row) => row['name']),
      contains('words'),
    );
  });

  test('an ayah stored before glosses existed reads back without them',
      () async {
    // The column is null on every pre-existing row, which must read as "no
    // words" rather than crash. The glosses arrive when the edition is
    // reinstalled.
    await seedV1();

    final AppDatabase upgraded = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: path,
    );
    addTearDown(upgraded.close);

    final Ayah? ayah = await AyahDao(upgraded)
        .byVerseKey('saheeh_international', '2:255');
    expect(ayah, isNotNull);
    expect(ayah!.hasWords, isFalse);
    expect(ayah.translationText, 'A translation.');
  });

  test('words round-trip through storage', () async {
    final AppDatabase database = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: path,
    );
    addTearDown(database.close);
    final AyahDao dao = AyahDao(database);

    await dao.replaceEdition(
      'saheeh_international',
      'saheeh_international',
      const <Ayah>[
        Ayah(
          id: 'saheeh_international:1:1',
          editionId: 'saheeh_international',
          ordinal: 1,
          surahNumber: 1,
          ayahNumber: 1,
          arabicText: 'نص',
          words: <AyahWord>[
            AyahWord(
              arabic: 'بِسْمِ',
              translation: 'In (the) name',
              transliteration: "bis'mi",
            ),
            AyahWord(arabic: 'ٱللَّهِ', translation: '(of) Allah'),
          ],
        ),
      ],
      const <Surah>[],
    );

    final Ayah? read = await dao.byOrdinal('saheeh_international', 1);
    expect(read!.words, hasLength(2));
    expect(read.words.first.arabic, 'بِسْمِ');
    expect(read.words.first.translation, 'In (the) name');
    expect(read.words.first.transliteration, "bis'mi");
    // A word the source gave no transliteration for keeps none.
    expect(read.words.last.transliteration, isNull);
  });

  test('an ayah with no words stores nothing rather than an empty array',
      () async {
    final AppDatabase database = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: path,
    );
    addTearDown(database.close);
    final AyahDao dao = AyahDao(database);

    await dao.replaceEdition(
      'e',
      'e',
      const <Ayah>[
        Ayah(
          id: 'e:1:1',
          editionId: 'e',
          ordinal: 1,
          surahNumber: 1,
          ayahNumber: 1,
          arabicText: 'نص',
        ),
      ],
      const <Surah>[],
    );

    final Database db = await database.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.ayahTable,
      columns: <String>['words'],
    );
    expect(rows.single['words'], isNull);
  });
}
