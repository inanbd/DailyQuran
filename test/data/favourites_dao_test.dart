import 'package:daily_quran/data/local/app_database.dart';
import 'package:daily_quran/data/local/favourites_dao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late FavouritesDao dao;

  setUp(() {
    database = AppDatabase(
      factoryOverride: databaseFactoryFfi,
      pathOverride: inMemoryDatabasePath,
    );
    dao = FavouritesDao(database);
  });

  tearDown(() => database.close());

  test('a saved ayah reads back as a favourite', () async {
    expect(await dao.isFavourite('quran', '2:255'), isFalse);

    await dao.add('quran', '2:255', 262);

    expect(await dao.isFavourite('quran', '2:255'), isTrue);
    expect(await dao.count(), 1);
  });

  test('removing clears it again', () async {
    await dao.add('quran', '2:255', 262);
    await dao.remove('quran', '2:255');

    expect(await dao.isFavourite('quran', '2:255'), isFalse);
    expect(await dao.count(), 0);
  });

  test('saving the same ayah twice keeps one row', () async {
    await dao.add('quran', '2:255', 262);
    await dao.add('quran', '2:255', 262);

    expect(await dao.count(), 1);
  });

  test('the same verse key in two scopes is two favourites', () async {
    await dao.add('quran', '1:1', 1);
    await dao.add('dev_sample', '1:1', 1);

    expect(await dao.count(), 2);
    expect(await dao.isFavourite('quran', '1:1'), isTrue);
    expect(await dao.isFavourite('dev_sample', '1:1'), isTrue);
  });

  test('favourites come back newest first', () async {
    final DateTime base = DateTime(2026, 3, 1, 12);
    await dao.add('quran', '18:10', 2150, at: base);
    await dao.add('quran', '2:255', 262, at: base.add(const Duration(hours: 2)));
    await dao.add('quran', '1:5', 5, at: base.add(const Duration(hours: 1)));

    final List<FavouriteRecord> all = await dao.all();

    expect(
      all.map((FavouriteRecord r) => r.verseKey).toList(),
      <String>['2:255', '1:5', '18:10'],
    );
    expect(all.first.scope, 'quran');
    expect(all.first.ordinal, 262);
  });

  test('re-saving moves a favourite back to the top', () async {
    final DateTime base = DateTime(2026, 3, 1, 12);
    await dao.add('quran', '1:1', 1, at: base);
    await dao.add('quran', '1:2', 2, at: base.add(const Duration(hours: 1)));

    await dao.add('quran', '1:1', 1, at: base.add(const Duration(hours: 5)));

    final List<FavouriteRecord> all = await dao.all();
    expect(
      all.map((FavouriteRecord r) => r.verseKey).toList(),
      <String>['1:1', '1:2'],
    );
  });
}
