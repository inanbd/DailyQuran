import 'package:sqflite/sqflite.dart';

import '../../domain/entities/reading_day.dart';
import 'app_database.dart';

/// Storage for the reader's reading days: time read, and goals met.
class ActivityDao {
  ActivityDao(this._database);

  final AppDatabase _database;

  Future<void> addReadingTime(DateTime day, int seconds) async {
    if (seconds <= 0) return;
    final Database db = await _database.database;
    // Insert-then-add rather than an UPSERT, which the SQLite on older
    // Android versions does not understand. In one transaction, so two saves
    // racing each other on the same day both count.
    await db.transaction((Transaction txn) async {
      final String key = dayKey(day);
      await txn.rawInsert(
        'INSERT OR IGNORE INTO ${AppDatabase.readingDaysTable} (day, seconds) '
        'VALUES (?, 0)',
        <Object?>[key],
      );
      await txn.rawUpdate(
        'UPDATE ${AppDatabase.readingDaysTable} SET seconds = seconds + ? '
        'WHERE day = ?',
        <Object?>[seconds, key],
      );
    });
  }

  Future<bool> markGoalMet(DateTime day, DateTime at) async {
    final Database db = await _database.database;
    return db.transaction((Transaction txn) async {
      final String key = dayKey(day);
      await txn.rawInsert(
        'INSERT OR IGNORE INTO ${AppDatabase.readingDaysTable} (day, seconds) '
        'VALUES (?, 0)',
        <Object?>[key],
      );
      final int changed = await txn.update(
        AppDatabase.readingDaysTable,
        <String, Object?>{'goal_met_at': at.millisecondsSinceEpoch},
        where: 'day = ? AND goal_met_at IS NULL',
        whereArgs: <Object?>[key],
      );
      return changed > 0;
    });
  }

  Future<ReadingDay> dayOf(DateTime day) async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.readingDaysTable,
      where: 'day = ?',
      whereArgs: <Object?>[dayKey(day)],
      limit: 1,
    );
    return rows.isEmpty ? ReadingDay.empty(day) : _fromRow(rows.first);
  }

  Future<List<ReadingDay>> daysBetween(DateTime from, DateTime to) async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.readingDaysTable,
      where: 'day BETWEEN ? AND ?',
      whereArgs: <Object?>[dayKey(from), dayKey(to)],
    );
    final Map<String, ReadingDay> recorded = <String, ReadingDay>{
      for (final Map<String, Object?> row in rows)
        row['day']! as String: _fromRow(row),
    };

    final List<ReadingDay> result = <ReadingDay>[];
    for (DateTime day = DateTime(from.year, from.month, from.day);
        !day.isAfter(to);
        day = DateTime(day.year, day.month, day.day + 1)) {
      result.add(recorded[dayKey(day)] ?? ReadingDay.empty(day));
    }
    return result;
  }

  Future<List<DateTime>> goalMetDays() async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.readingDaysTable,
      columns: <String>['day'],
      where: 'goal_met_at IS NOT NULL',
      orderBy: 'day DESC',
    );
    return <DateTime>[
      for (final Map<String, Object?> row in rows)
        ?parseDayKey(row['day']! as String),
    ];
  }

  /// `yyyy-MM-dd`, which sorts in date order as plain text.
  static String dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static DateTime? parseDayKey(String key) {
    final List<String> parts = key.split('-');
    if (parts.length != 3) return null;
    final int? year = int.tryParse(parts[0]);
    final int? month = int.tryParse(parts[1]);
    final int? day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  static ReadingDay _fromRow(Map<String, Object?> row) {
    final Object? metAt = row['goal_met_at'];
    return ReadingDay(
      day: parseDayKey(row['day']! as String) ?? DateTime(1970),
      seconds: (row['seconds'] as int?) ?? 0,
      goalMetAt:
          metAt is int ? DateTime.fromMillisecondsSinceEpoch(metAt) : null,
    );
  }
}
