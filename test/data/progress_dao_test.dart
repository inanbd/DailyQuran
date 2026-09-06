import 'package:daily_quran/data/local/app_database.dart';
import 'package:daily_quran/data/local/progress_dao.dart';
import 'package:daily_quran/domain/entities/reading_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase database;
  late ProgressDao dao;

  const String scope = 'quran';
  const int total = 10;

  /// Verse keys for a scope laid out as two surahs of five.
  String verse(int ordinal) => '${((ordinal - 1) ~/ 5) + 1}:${((ordinal - 1) % 5) + 1}';

  setUp(() {
    database = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: inMemoryDatabasePath,
    );
    dao = ProgressDao(database);
  });

  tearDown(() => database.close());

  test('an untouched scope reports nothing read', () async {
    final ReadingProgress progress = await dao.progressFor(scope, total);
    expect(progress.totalRead, 0);
    expect(progress.currentOrdinal, 1);
    expect(progress.hasStarted, isFalse);
    expect(progress.isComplete, isFalse);
    expect(await dao.firstUnreadOrdinal(scope, total), 1);
  });

  test('marking read records progress and stamps the start date', () async {
    final ReadingProgress progress =
        await dao.markRead(scope, verse(1), 1, total);
    expect(progress.totalRead, 1);
    expect(progress.currentOrdinal, 1);
    expect(progress.startedAt, isNotNull);
    expect(progress.lastReadAt, isNotNull);
    expect(await dao.isRead(scope, verse(1)), isTrue);
    expect(await dao.firstUnreadOrdinal(scope, total), 2);
  });

  test('marking read twice does not double-count', () async {
    await dao.markRead(scope, verse(1), 1, total);
    final ReadingProgress progress =
        await dao.markRead(scope, verse(1), 1, total);
    expect(progress.totalRead, 1);
  });

  test('skipping ahead leaves the gap unread', () async {
    await dao.markRead(scope, verse(1), 1, total);
    await dao.markRead(scope, verse(5), 5, total);

    expect(await dao.firstUnreadOrdinal(scope, total), 2);
    final ReadingProgress progress = await dao.progressFor(scope, total);
    expect(progress.totalRead, 2);
    expect(progress.isComplete, isFalse);
    expect(await dao.readOrdinalsIn(scope, 1, 10), <int>{1, 5});
  });

  test('the first unread is found after a long contiguous run', () async {
    for (int i = 1; i <= 7; i++) {
      await dao.markRead(scope, verse(i), i, total);
    }
    expect(await dao.firstUnreadOrdinal(scope, total), 8);
  });

  test('reading everything completes the scope', () async {
    for (int i = 1; i <= total; i++) {
      await dao.markRead(scope, verse(i), i, total);
    }
    final ReadingProgress progress = await dao.progressFor(scope, total);
    expect(progress.totalRead, total);
    expect(progress.isComplete, isTrue);
    expect(progress.completedAt, isNotNull);
    expect(progress.percentage, 100);
    expect(await dao.firstUnreadOrdinal(scope, total), isNull);
  });

  test('un-reading one ayah re-opens a completed scope', () async {
    for (int i = 1; i <= total; i++) {
      await dao.markRead(scope, verse(i), i, total);
    }
    final ReadingProgress progress =
        await dao.markUnread(scope, verse(4), total);

    expect(progress.totalRead, total - 1);
    expect(progress.isComplete, isFalse);
    expect(progress.completedAt, isNull);
    expect(await dao.firstUnreadOrdinal(scope, total), 4);
  });

  test('moving position does not mark anything read', () async {
    final ReadingProgress progress =
        await dao.setCurrentOrdinal(scope, 6, total);
    expect(progress.currentOrdinal, 6);
    expect(progress.totalRead, 0);
    expect(progress.lastReadAt, isNull);
    expect(await dao.firstUnreadOrdinal(scope, total), 1);
  });

  test('each scope keeps its own progress', () async {
    await dao.markRead(scope, verse(1), 1, total);
    await dao.markRead('dev_sample', '1:1', 1, 20);
    await dao.markRead('dev_sample', '1:2', 2, 20);

    expect((await dao.progressFor(scope, total)).totalRead, 1);
    expect((await dao.progressFor('dev_sample', 20)).totalRead, 2);

    final List<ReadingProgress> all = await dao.allProgress(
      <String, int>{scope: total, 'dev_sample': 20},
    );
    expect(all.length, 2);
  });

  test('two translations of the Qur’an share one place', () async {
    // The whole point of a scope: reading in one translation and coming back in
    // another is the same reading, not two.
    await dao.markRead(scope, '1:1', 1, total);
    await dao.markRead(scope, '1:2', 2, total);
    await dao.setCurrentOrdinal(scope, 3, total);

    final ReadingProgress progress = await dao.progressFor(scope, total);
    expect(progress.totalRead, 2);
    expect(progress.currentOrdinal, 3);
    expect(await dao.firstUnreadOrdinal(scope, total), 3);
  });

  test('resetting clears read state so it can be read again', () async {
    for (int i = 1; i <= total; i++) {
      await dao.markRead(scope, verse(i), i, total);
    }
    final ReadingProgress progress = await dao.resetScope(scope, total);

    expect(progress.totalRead, 0);
    expect(progress.currentOrdinal, 1);
    expect(progress.startedAt, isNull);
    expect(progress.completedAt, isNull);
    expect(await dao.firstUnreadOrdinal(scope, total), 1);
  });

  test('rows beyond the edition size are not counted', () async {
    // A dataset that shrank on re-import must not report >100% read.
    await dao.markRead(scope, '1:1', 1, total);
    await dao.markRead(scope, '99:1', 99, total);

    final ReadingProgress progress = await dao.progressFor(scope, total);
    expect(progress.totalRead, 1);
    expect(progress.fraction, lessThanOrEqualTo(1.0));
  });
}
