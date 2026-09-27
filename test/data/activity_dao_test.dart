import 'package:daily_quran/data/local/activity_dao.dart';
import 'package:daily_quran/data/local/app_database.dart';
import 'package:daily_quran/data/local/progress_dao.dart';
import 'package:daily_quran/domain/entities/reading_day.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The reader's reading days and milestones, as stored.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase database;
  late ActivityDao dao;

  final DateTime today = DateTime(2026, 1, 7);

  setUp(() {
    database = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: inMemoryDatabasePath,
    );
    dao = ActivityDao(database);
  });

  tearDown(() => database.close());

  test('a day with nothing recorded is empty', () async {
    final ReadingDay day = await dao.dayOf(today);

    expect(day.day, today);
    expect(day.seconds, 0);
    expect(day.goalMet, isFalse);
  });

  test('reading time adds up through the day', () async {
    await dao.addReadingTime(today, 40);
    await dao.addReadingTime(today, 25);

    expect((await dao.dayOf(today)).seconds, 65);
  });

  test('reading time on one day leaves the next alone', () async {
    await dao.addReadingTime(today, 40);

    expect((await dao.dayOf(DateTime(2026, 1, 8))).seconds, 0);
  });

  test('a day is the same day whatever time it is asked about', () async {
    await dao.addReadingTime(DateTime(2026, 1, 7, 23, 59), 30);

    expect((await dao.dayOf(DateTime(2026, 1, 7, 6, 0))).seconds, 30);
  });

  test('a day’s goal is met once', () async {
    final DateTime at = DateTime(2026, 1, 7, 9, 30);

    expect(await dao.markGoalMet(today, at), isTrue);
    expect(await dao.markGoalMet(today, at.add(const Duration(hours: 1))),
        isFalse);

    final ReadingDay day = await dao.dayOf(today);
    expect(day.goalMet, isTrue);
    expect(day.goalMetAt, at);
  });

  test('meeting the goal keeps the day’s reading time', () async {
    await dao.addReadingTime(today, 300);
    await dao.markGoalMet(today, DateTime(2026, 1, 7, 9));
    await dao.addReadingTime(today, 60);

    final ReadingDay day = await dao.dayOf(today);
    expect(day.seconds, 360);
    expect(day.goalMet, isTrue);
  });

  test('a run of days comes back whole, the gaps filled in', () async {
    await dao.addReadingTime(DateTime(2026, 1, 5), 120);
    await dao.addReadingTime(today, 60);

    final List<ReadingDay> days =
        await dao.daysBetween(DateTime(2026, 1, 4), today);

    expect(days.map((ReadingDay day) => day.day), <DateTime>[
      DateTime(2026, 1, 4),
      DateTime(2026, 1, 5),
      DateTime(2026, 1, 6),
      today,
    ]);
    expect(days.map((ReadingDay day) => day.seconds), <int>[0, 120, 0, 60]);
  });

  test('goal days come back most recent first', () async {
    await dao.markGoalMet(DateTime(2026, 1, 5), DateTime(2026, 1, 5, 9));
    await dao.markGoalMet(today, DateTime(2026, 1, 7, 9));
    await dao.addReadingTime(DateTime(2026, 1, 6), 45);

    expect(
      await dao.goalMetDays(),
      <DateTime>[today, DateTime(2026, 1, 5)],
    );
  });

  test('day keys sort as dates', () {
    expect(ActivityDao.dayKey(DateTime(2026, 1, 7)), '2026-01-07');
    expect(ActivityDao.parseDayKey('2026-12-31'), DateTime(2026, 12, 31));
    expect(ActivityDao.parseDayKey('nonsense'), isNull);
  });

  group('milestones', () {
    late ProgressDao progress;

    setUp(() => progress = ProgressDao(database));

    test('are reached once per reading', () async {
      final DateTime at = DateTime(2026, 1, 7, 9);

      expect(await progress.reachMilestone('quran', 10, at), isTrue);
      expect(await progress.reachMilestone('quran', 10, at), isFalse);
      // The plan's reading passes its own.
      expect(await progress.reachMilestone('quran#plan', 10, at), isTrue);
    });

    test('are passed afresh once a reading is started again', () async {
      final DateTime at = DateTime(2026, 1, 7, 9);
      await progress.reachMilestone('quran#plan', 10, at);
      await progress.reachMilestone('quran', 10, at);

      await progress.resetScope('quran#plan', 10);

      expect(await progress.reachMilestone('quran#plan', 10, at), isTrue);
      // Starting the plan over leaves the Daily Ayah's alone.
      expect(await progress.reachMilestone('quran', 10, at), isFalse);
    });
  });
}
