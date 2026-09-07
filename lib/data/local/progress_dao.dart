import 'package:sqflite/sqflite.dart';

import '../../domain/entities/reading_progress.dart';
import 'app_database.dart';

/// Reading progress storage.
///
/// Read state is stored as one row per ayah actually read, keyed by verse key
/// within a scope. Nothing is ever inferred in bulk, which is what guarantees
/// that skipping ahead — or missing a week — leaves the skipped ayat unread.
class ProgressDao {
  ProgressDao(this._database);

  final AppDatabase _database;

  Future<ReadingProgress> progressFor(String scope, int totalAyah) async {
    final Database db = await _database.database;
    return _read(db, scope, totalAyah);
  }

  Future<List<ReadingProgress>> allProgress(Map<String, int> totals) async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.progressTable,
      orderBy: 'last_read_at DESC',
    );
    final List<ReadingProgress> result = <ReadingProgress>[];
    for (final Map<String, Object?> row in rows) {
      final String id = row['scope']! as String;
      result.add(await _read(db, id, totals[id] ?? 0));
    }
    return result;
  }

  Future<ReadingProgress> markRead(
    String scope,
    String verseKey,
    int ordinal,
    int totalAyah, {
    DateTime? at,
  }) async {
    final Database db = await _database.database;
    final int timestamp = (at ?? DateTime.now()).millisecondsSinceEpoch;
    await db.transaction((Transaction txn) async {
      await txn.insert(
        AppDatabase.readTable,
        <String, Object?>{
          'scope': scope,
          'verse_key': verseKey,
          'ordinal': ordinal,
          'read_at': timestamp,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _touch(
        txn,
        scope,
        currentOrdinal: ordinal,
        lastReadAt: timestamp,
        startedAtIfMissing: timestamp,
      );
      await _refreshCompletion(txn, scope, totalAyah, timestamp);
    });
    return _read(db, scope, totalAyah);
  }

  Future<ReadingProgress> markUnread(
    String scope,
    String verseKey,
    int totalAyah,
  ) async {
    final Database db = await _database.database;
    await db.transaction((Transaction txn) async {
      await txn.delete(
        AppDatabase.readTable,
        where: 'scope = ? AND verse_key = ?',
        whereArgs: <Object?>[scope, verseKey],
      );
      // Un-reading anything necessarily un-completes the reading.
      await txn.update(
        AppDatabase.progressTable,
        <String, Object?>{'completed_at': null},
        where: 'scope = ?',
        whereArgs: <Object?>[scope],
      );
      await _refreshCompletion(
        txn,
        scope,
        totalAyah,
        DateTime.now().millisecondsSinceEpoch,
      );
    });
    return _read(db, scope, totalAyah);
  }

  Future<ReadingProgress> setCurrentOrdinal(
    String scope,
    int ordinal,
    int totalAyah,
  ) async {
    final Database db = await _database.database;
    await db.transaction((Transaction txn) async {
      await _touch(txn, scope, currentOrdinal: ordinal);
    });
    return _read(db, scope, totalAyah);
  }

  Future<bool> isRead(String scope, String verseKey) async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.readTable,
      columns: <String>['verse_key'],
      where: 'scope = ? AND verse_key = ?',
      whereArgs: <Object?>[scope, verseKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<Set<int>> readOrdinalsIn(String scope, int from, int to) async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.readTable,
      columns: <String>['ordinal'],
      where: 'scope = ? AND ordinal BETWEEN ? AND ?',
      whereArgs: <Object?>[scope, from, to],
    );
    return rows
        .map((Map<String, Object?> row) => row['ordinal']! as int)
        .toSet();
  }

  /// How many ayat in [scope] were read at or after [since].
  ///
  /// This is how much of a plan's portion is done: the period's start goes in,
  /// and what comes back is what has actually been read in it. Counting rows
  /// rather than storing a per-day tally means the answer stays correct however
  /// the reader moved about — reading ahead, going back, changing translation.
  Future<int> readCountSince(String scope, DateTime since) async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.readTable} '
      'WHERE scope = ? AND read_at >= ?',
      <Object?>[scope, since.millisecondsSinceEpoch],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// Lowest unread ordinal in `1..totalAyah`, or null when all are read.
  ///
  /// Resolved with two indexed queries rather than by loading the read set, so
  /// it stays cheap across 6,236 ayat.
  Future<int?> firstUnreadOrdinal(String scope, int totalAyah) async {
    if (totalAyah <= 0) return null;
    final Database db = await _database.database;
    return _firstUnread(db, scope, totalAyah);
  }

  Future<ReadingProgress> resetScope(
    String scope,
    int totalAyah,
  ) async {
    final Database db = await _database.database;
    await db.transaction((Transaction txn) async {
      await txn.delete(
        AppDatabase.readTable,
        where: 'scope = ?',
        whereArgs: <Object?>[scope],
      );
      await txn.delete(
        AppDatabase.progressTable,
        where: 'scope = ?',
        whereArgs: <Object?>[scope],
      );
    });
    return _read(db, scope, totalAyah);
  }

  static Future<int?> _firstUnread(
    DatabaseExecutor db,
    String scope,
    int totalAyah,
  ) async {
    final List<Map<String, Object?>> firstRow = await db.query(
      AppDatabase.readTable,
      columns: <String>['ordinal'],
      where: 'scope = ? AND ordinal = 1',
      whereArgs: <Object?>[scope],
      limit: 1,
    );
    if (firstRow.isEmpty) return 1;

    // The lowest ordinal that is read while its successor is not: the start of
    // the first gap.
    final List<Map<String, Object?>> gap = await db.rawQuery(
      '''
      SELECT MIN(t.ordinal + 1) AS next FROM ${AppDatabase.readTable} t
      WHERE t.scope = ?
        AND NOT EXISTS (
          SELECT 1 FROM ${AppDatabase.readTable} r
          WHERE r.scope = t.scope AND r.ordinal = t.ordinal + 1
        )
      ''',
      <Object?>[scope],
    );
    final Object? next = gap.isEmpty ? null : gap.first['next'];
    if (next is! int) return null;
    if (next > totalAyah) return null;
    return next;
  }

  static Future<void> _touch(
    Transaction txn,
    String scope, {
    int? currentOrdinal,
    int? lastReadAt,
    int? startedAtIfMissing,
  }) async {
    final List<Map<String, Object?>> existing = await txn.query(
      AppDatabase.progressTable,
      where: 'scope = ?',
      whereArgs: <Object?>[scope],
      limit: 1,
    );

    if (existing.isEmpty) {
      await txn.insert(AppDatabase.progressTable, <String, Object?>{
        'scope': scope,
        'current_ordinal': currentOrdinal ?? 1,
        'started_at': startedAtIfMissing,
        'last_read_at': lastReadAt,
        'completed_at': null,
      });
      return;
    }

    final Map<String, Object?> update = <String, Object?>{};
    if (currentOrdinal != null) update['current_ordinal'] = currentOrdinal;
    if (lastReadAt != null) update['last_read_at'] = lastReadAt;
    if (startedAtIfMissing != null && existing.first['started_at'] == null) {
      update['started_at'] = startedAtIfMissing;
    }
    if (update.isEmpty) return;

    await txn.update(
      AppDatabase.progressTable,
      update,
      where: 'scope = ?',
      whereArgs: <Object?>[scope],
    );
  }

  /// Stamps or clears `completed_at` to match the current read count.
  static Future<void> _refreshCompletion(
    Transaction txn,
    String scope,
    int totalAyah,
    int timestamp,
  ) async {
    if (totalAyah <= 0) return;
    final int? firstUnread = await _firstUnread(txn, scope, totalAyah);
    if (firstUnread == null) {
      await txn.update(
        AppDatabase.progressTable,
        <String, Object?>{'completed_at': timestamp},
        where: 'scope = ? AND completed_at IS NULL',
        whereArgs: <Object?>[scope],
      );
    } else {
      await txn.update(
        AppDatabase.progressTable,
        <String, Object?>{'completed_at': null},
        where: 'scope = ? AND completed_at IS NOT NULL',
        whereArgs: <Object?>[scope],
      );
    }
  }

  static Future<ReadingProgress> _read(
    Database db,
    String scope,
    int totalAyah,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.progressTable,
      where: 'scope = ?',
      whereArgs: <Object?>[scope],
      limit: 1,
    );

    final List<Map<String, Object?>> countRows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.readTable} '
      'WHERE scope = ? AND ordinal >= 1 AND ordinal <= ?',
      <Object?>[scope, totalAyah],
    );
    final int totalRead = Sqflite.firstIntValue(countRows) ?? 0;

    if (rows.isEmpty) {
      return ReadingProgress(
        scope: scope,
        currentOrdinal: 1,
        totalRead: totalRead,
        totalAyah: totalAyah,
      );
    }

    final Map<String, Object?> row = rows.first;
    return ReadingProgress(
      scope: scope,
      currentOrdinal: (row['current_ordinal'] as int?) ?? 1,
      totalRead: totalRead,
      totalAyah: totalAyah,
      startedAt: _time(row['started_at']),
      lastReadAt: _time(row['last_read_at']),
      completedAt: _time(row['completed_at']),
    );
  }

  static DateTime? _time(Object? value) =>
      value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;
}
