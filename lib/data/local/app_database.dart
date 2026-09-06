import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens and migrates the app's SQLite database.
///
/// The database holds two very different kinds of data: a local *copy* of an
/// edition's text (so reading works offline and paging 6,236 ayat is cheap) and
/// the reader's own progress and favourites. Only the latter is irreplaceable —
/// ayah rows can always be re-imported from the content source.
class AppDatabase {
  AppDatabase({this.factoryOverride, this.pathOverride});

  static const String fileName = 'daily_quran.db';
  static const int schemaVersion = 2;

  static const String editionsTable = 'editions';
  static const String ayahTable = 'ayah';
  static const String surahsTable = 'surahs';
  static const String progressTable = 'reading_progress';
  static const String readTable = 'read_ayah';
  static const String favouritesTable = 'favourite_ayah';

  /// Injected in tests to run against an in-memory FFI database.
  final DatabaseFactory? factoryOverride;

  /// Injected in tests, or to place the database file somewhere other than the
  /// platform default.
  final String? pathOverride;

  Database? _db;
  Future<Database>? _opening;

  /// The open database, opening it on first use. Concurrent callers share a
  /// single open operation.
  Future<Database> get database async {
    final Database? existing = _db;
    if (existing != null && existing.isOpen) return existing;
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  Future<Database> _open() async {
    final DatabaseFactory factory = factoryOverride ?? databaseFactory;
    final String path =
        pathOverride ?? p.join(await factory.getDatabasesPath(), fileName);
    final Database db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (Database db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (Database db, int version) async {
          await _createSchema(db);
        },
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
          // Migrations are additive. Ayah and surah tables may be dropped and
          // re-imported; the reader's own data — progress and favourites —
          // must survive every upgrade.
          if (oldVersion < 2) {
            // Word glosses arrived after the first release. Adding the column
            // leaves it null on every existing row, which reads back as an
            // ayah with no words until the edition is reinstalled.
            await db.execute(
              'ALTER TABLE $ayahTable ADD COLUMN words TEXT',
            );
          }
        },
      ),
    );
    _db = db;
    return db;
  }

  static Future<void> _createSchema(Database db) async {
    final Batch batch = db.batch();

    batch.execute('''
      CREATE TABLE $editionsTable (
        id TEXT PRIMARY KEY,
        slug TEXT NOT NULL,
        installed_count INTEGER NOT NULL DEFAULT 0,
        installed_at INTEGER
      )
    ''');

    batch.execute('''
      CREATE TABLE $ayahTable (
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
        source TEXT,
        -- The ayah's words and their glosses, as a JSON array. They are a
        -- value of the ayah: always read with it, never queried on their
        -- own, so a column beats a second table and an extra join.
        words TEXT
      )
    ''');
    batch.execute(
      'CREATE UNIQUE INDEX idx_ayah_position ON $ayahTable (edition_id, ordinal)',
    );
    // Favourites and read state are stored by verse key, so looking an ayah up
    // by key is on the hot path for every screen that shows a saved ayah.
    batch.execute(
      'CREATE UNIQUE INDEX idx_ayah_verse ON $ayahTable (edition_id, verse_key)',
    );
    batch.execute(
      'CREATE INDEX idx_ayah_surah ON $ayahTable (edition_id, surah_number, ordinal)',
    );

    batch.execute('''
      CREATE TABLE $surahsTable (
        edition_id TEXT NOT NULL,
        number INTEGER NOT NULL,
        name_arabic TEXT NOT NULL DEFAULT '',
        name_transliterated TEXT NOT NULL DEFAULT '',
        name_english TEXT NOT NULL DEFAULT '',
        ayah_count INTEGER NOT NULL DEFAULT 0,
        revelation_place TEXT NOT NULL DEFAULT 'unknown',
        PRIMARY KEY (edition_id, number)
      )
    ''');

    // Keyed by scope, not by edition: every complete edition of the Qur'an
    // shares one, so changing translation keeps the reader's place.
    batch.execute('''
      CREATE TABLE $progressTable (
        scope TEXT PRIMARY KEY,
        current_ordinal INTEGER NOT NULL DEFAULT 1,
        started_at INTEGER,
        last_read_at INTEGER,
        completed_at INTEGER
      )
    ''');

    batch.execute('''
      CREATE TABLE $readTable (
        scope TEXT NOT NULL,
        verse_key TEXT NOT NULL,
        ordinal INTEGER NOT NULL,
        read_at INTEGER NOT NULL,
        PRIMARY KEY (scope, verse_key)
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_read_position ON $readTable (scope, ordinal)',
    );

    batch.execute('''
      CREATE TABLE $favouritesTable (
        scope TEXT NOT NULL,
        verse_key TEXT NOT NULL,
        ordinal INTEGER NOT NULL,
        saved_at INTEGER NOT NULL,
        PRIMARY KEY (scope, verse_key)
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_favourite_saved ON $favouritesTable (saved_at DESC)',
    );

    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    final Database? db = _db;
    _db = null;
    if (db != null && db.isOpen) await db.close();
  }
}
