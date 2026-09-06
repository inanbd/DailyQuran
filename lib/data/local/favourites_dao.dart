import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// One saved-ayah row, before its text has been resolved.
class FavouriteRecord {
  const FavouriteRecord({
    required this.scope,
    required this.verseKey,
    required this.ordinal,
    required this.savedAt,
  });

  final String scope;
  final String verseKey;
  final int ordinal;
  final DateTime savedAt;
}

/// Favourite storage.
///
/// Rows are keyed by scope and verse key rather than by edition, so saving the
/// same ayah twice is idempotent and switching translation neither duplicates
/// nor loses anything.
class FavouritesDao {
  FavouritesDao(this._database);

  final AppDatabase _database;

  Future<List<FavouriteRecord>> all() async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.favouritesTable,
      orderBy: 'saved_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<bool> isFavourite(String scope, String verseKey) async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.favouritesTable,
      columns: <String>['verse_key'],
      where: 'scope = ? AND verse_key = ?',
      whereArgs: <Object?>[scope, verseKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> add(
    String scope,
    String verseKey,
    int ordinal, {
    DateTime? at,
  }) async {
    final Database db = await _database.database;
    await db.insert(
      AppDatabase.favouritesTable,
      <String, Object?>{
        'scope': scope,
        'verse_key': verseKey,
        'ordinal': ordinal,
        'saved_at': (at ?? DateTime.now()).millisecondsSinceEpoch,
      },
      // Re-saving keeps the row but refreshes when it was saved, which is what
      // puts it back at the top of the list.
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> remove(String scope, String verseKey) async {
    final Database db = await _database.database;
    await db.delete(
      AppDatabase.favouritesTable,
      where: 'scope = ? AND verse_key = ?',
      whereArgs: <Object?>[scope, verseKey],
    );
  }

  Future<int> count() async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.favouritesTable}',
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  static FavouriteRecord _fromRow(Map<String, Object?> row) => FavouriteRecord(
        scope: row['scope']! as String,
        verseKey: row['verse_key']! as String,
        ordinal: (row['ordinal'] as int?) ?? 1,
        savedAt: DateTime.fromMillisecondsSinceEpoch(
          (row['saved_at'] as int?) ?? 0,
        ),
      );
}
