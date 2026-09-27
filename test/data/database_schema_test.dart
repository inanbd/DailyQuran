import 'dart:io';

import 'package:daily_quran/data/local/app_database.dart';
import 'package:daily_quran/data/local/favourites_dao.dart';
import 'package:daily_quran/data/local/progress_dao.dart';
import 'package:daily_quran/domain/entities/reading_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Guards the shape of the database and, more importantly, that the reader's
/// own data survives the app being closed and reopened.
///
/// There is no migration to test yet — the schema is at v1 — but the tables
/// that hold irreplaceable data are named here so that a future migration has
/// something concrete to keep working.
void main() {
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late String path;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('daily_quran_schema');
    path = p.join(directory.path, AppDatabase.fileName);
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  Future<List<String>> tables(Database db) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return rows.map((Map<String, Object?> r) => r['name']! as String).toList();
  }

  test('a fresh install creates every table the app reads', () async {
    final AppDatabase database = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: path,
    );
    addTearDown(database.close);
    final Database db = await database.database;

    expect(await db.getVersion(), AppDatabase.schemaVersion);
    expect(
      await tables(db),
      containsAll(<String>[
        AppDatabase.editionsTable,
        AppDatabase.ayahTable,
        AppDatabase.surahsTable,
        AppDatabase.progressTable,
        AppDatabase.readTable,
        AppDatabase.favouritesTable,
        AppDatabase.readingDaysTable,
        AppDatabase.milestonesTable,
      ]),
    );
  });

  test('progress and favourites survive closing and reopening', () async {
    final AppDatabase first = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: path,
    );
    await ProgressDao(first).markRead('quran', '2:255', 262, 6236);
    await FavouritesDao(first).add('quran', '2:255', 262);
    await first.close();

    final AppDatabase second = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: path,
    );
    addTearDown(second.close);

    final ReadingProgress progress =
        await ProgressDao(second).progressFor('quran', 6236);
    expect(progress.totalRead, 1);
    expect(progress.currentOrdinal, 262);
    expect(await FavouritesDao(second).isFavourite('quran', '2:255'), isTrue);
  });

  test('reading progress is keyed by scope, not by edition', () async {
    // Reinstalling or switching translation must not be able to strand a
    // reader's place under an edition id.
    final AppDatabase database = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: path,
    );
    addTearDown(database.close);
    final Database db = await database.database;

    final List<Map<String, Object?>> columns =
        await db.rawQuery('PRAGMA table_info(${AppDatabase.progressTable})');
    expect(
      columns.map((Map<String, Object?> row) => row['name']),
      contains('scope'),
    );

    final List<Map<String, Object?>> readColumns =
        await db.rawQuery('PRAGMA table_info(${AppDatabase.readTable})');
    expect(
      readColumns.map((Map<String, Object?> row) => row['name']),
      containsAll(<String>['scope', 'verse_key']),
    );
  });
}
