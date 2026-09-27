import 'dart:io';

import 'package:daily_quran/data/local/activity_dao.dart';
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

  test('upgrading from v1 clears the stored text so glosses can arrive',
      () async {
    // Text stored before glosses existed has a null words column, and nothing
    // re-imports an edition that is already installed — so leaving those rows
    // in place would keep word-by-word permanently blank for a reader who
    // upgraded. Clearing them puts the edition back through the install path,
    // which joins the glosses on.
    await seedV1();

    final AppDatabase upgraded = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: path,
    );
    addTearDown(upgraded.close);

    final Ayah? ayah = await AyahDao(upgraded)
        .byVerseKey('saheeh_international', '2:255');
    expect(ayah, isNull);
    expect(await AyahDao(upgraded).countFor('saheeh_international'), 0);
  });

  test('a v2 install stranded with wordless text is cleared too', () async {
    // v2 added the words column but never refilled the rows already stored, so
    // anyone who upgraded to it is sitting on text that can never show
    // glosses. They must be rescued by the same clearing as a v1 reader.
    final Database db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (Database db, int version) async {
          await db.execute(_v1Ayah);
          await db.execute(_v1Progress);
          await db.execute(_v1Read);
          await db.execute(_v1Favourites);
          await db.execute('ALTER TABLE ayah ADD COLUMN words TEXT');
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
    await db.close();

    final AppDatabase upgraded = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: path,
    );
    addTearDown(upgraded.close);

    expect(await AyahDao(upgraded).countFor('saheeh_international'), 0);
    final ReadingProgress progress =
        await ProgressDao(upgraded).progressFor('quran', 6236);
    expect(progress.currentOrdinal, 262);
  });

  test('upgrading from v1 keeps the reader’s place while the text is refetched',
      () async {
    // The clearing above must never take progress or favourites with it.
    await seedV1();

    final AppDatabase upgraded = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: path,
    );
    addTearDown(upgraded.close);

    final ReadingProgress progress =
        await ProgressDao(upgraded).progressFor('quran', 6236);
    expect(progress.currentOrdinal, 262);
    expect(progress.totalRead, 1);
    expect(
      await FavouritesDao(upgraded).isFavourite('quran', '2:255'),
      isTrue,
    );
  });

  test('upgrading from v3 adds reading days and milestones, and keeps the rest',
      () async {
    // v3 is v1 with the words column. Its text was already refilled with
    // glosses, so this upgrade must leave it where it is.
    final Database db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (Database db, int version) async {
          await db.execute(_v1Ayah);
          await db.execute(_v1Progress);
          await db.execute(_v1Read);
          await db.execute(_v1Favourites);
          await db.execute('ALTER TABLE ayah ADD COLUMN words TEXT');
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
    await db.insert('read_ayah', <String, Object?>{
      'scope': 'quran',
      'verse_key': '2:255',
      'ordinal': 262,
      'read_at': 1700000000000,
    });
    await db.close();

    final AppDatabase upgraded = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: path,
    );
    addTearDown(upgraded.close);

    expect(await (await upgraded.database).getVersion(), 4);
    expect(await AyahDao(upgraded).countFor('saheeh_international'), 1);
    expect(
      (await ProgressDao(upgraded).progressFor('quran', 6236)).totalRead,
      1,
    );

    // The new tables are there, and empty: nothing is guessed at.
    final ActivityDao activity = ActivityDao(upgraded);
    expect(await activity.goalMetDays(), isEmpty);
    await activity.addReadingTime(DateTime(2026, 1, 7), 60);
    expect((await activity.dayOf(DateTime(2026, 1, 7))).seconds, 60);
    expect(
      await ProgressDao(upgraded)
          .reachMilestone('quran', 10, DateTime(2026, 1, 7)),
      isTrue,
    );
  });

  test('upgrading from v1 arrives with the reading-day tables too', () async {
    await seedV1();

    final AppDatabase upgraded = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: path,
    );
    addTearDown(upgraded.close);

    await ActivityDao(upgraded).addReadingTime(DateTime(2026, 1, 7), 30);
    expect(
      (await ActivityDao(upgraded).dayOf(DateTime(2026, 1, 7))).seconds,
      30,
    );
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
