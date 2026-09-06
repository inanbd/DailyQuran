import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/entities/ayah.dart';
import '../../domain/entities/ayah_word.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/surah.dart';
import 'app_database.dart';

/// Reads and writes the local copy of an edition's text.
class AyahDao {
  AyahDao(this._database);

  final AppDatabase _database;

  /// Replaces an edition's stored text in one transaction, so an interrupted
  /// import can never leave a half-installed edition behind.
  Future<void> replaceEdition(
    String editionId,
    String slug,
    List<Ayah> ayat,
    List<Surah> surahs,
  ) async {
    final Database db = await _database.database;
    await db.transaction((Transaction txn) async {
      await txn.delete(
        AppDatabase.ayahTable,
        where: 'edition_id = ?',
        whereArgs: <Object?>[editionId],
      );
      await txn.delete(
        AppDatabase.surahsTable,
        where: 'edition_id = ?',
        whereArgs: <Object?>[editionId],
      );

      final Batch batch = txn.batch();
      for (final Ayah ayah in ayat) {
        batch.insert(
          AppDatabase.ayahTable,
          _toRow(ayah),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final Surah surah in surahs) {
        batch.insert(
          AppDatabase.surahsTable,
          <String, Object?>{
            'edition_id': surah.editionId,
            'number': surah.number,
            'name_arabic': surah.nameArabic,
            'name_transliterated': surah.nameTransliterated,
            'name_english': surah.nameEnglish,
            'ayah_count': surah.ayahCount,
            'revelation_place': surah.revelationPlace.storageKey,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      batch.insert(
        AppDatabase.editionsTable,
        <String, Object?>{
          'id': editionId,
          'slug': slug,
          'installed_count': ayat.length,
          'installed_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await batch.commit(noResult: true);
    });
  }

  Future<int> countFor(String editionId) async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.ayahTable} WHERE edition_id = ?',
      <Object?>[editionId],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// Ids of every edition with text stored locally.
  Future<Set<String>> installedEditionIds() async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT DISTINCT edition_id AS id FROM ${AppDatabase.ayahTable}',
    );
    return rows.map((Map<String, Object?> row) => row['id']! as String).toSet();
  }

  Future<Ayah?> byOrdinal(String editionId, int ordinal) async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.ayahTable,
      where: 'edition_id = ? AND ordinal = ?',
      whereArgs: <Object?>[editionId, ordinal],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<Ayah?> byId(String ayahId) async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.ayahTable,
      where: 'id = ?',
      whereArgs: <Object?>[ayahId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// One ayah by its edition-independent key, e.g. `2:255`.
  Future<Ayah?> byVerseKey(String editionId, String verseKey) async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.ayahTable,
      where: 'edition_id = ? AND verse_key = ?',
      whereArgs: <Object?>[editionId, verseKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<List<Surah>> surahs(String editionId) async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.surahsTable,
      where: 'edition_id = ?',
      whereArgs: <Object?>[editionId],
      orderBy: 'number ASC',
    );
    return rows
        .map(
          (Map<String, Object?> row) => Surah(
            editionId: row['edition_id']! as String,
            number: row['number']! as int,
            nameArabic: (row['name_arabic'] as String?) ?? '',
            nameTransliterated: (row['name_transliterated'] as String?) ?? '',
            nameEnglish: (row['name_english'] as String?) ?? '',
            ayahCount: (row['ayah_count'] as int?) ?? 0,
            revelationPlace:
                RevelationPlace.fromStorage(row['revelation_place'] as String?),
          ),
        )
        .toList(growable: false);
  }

  /// The reading position of the first ayah of a surah, or null when the surah
  /// has no ayat stored against it.
  ///
  /// Surah metadata and ayah rows are imported separately, so a surah can
  /// legitimately exist with nothing pointing at it; the caller treats that as
  /// "not navigable" rather than an error.
  Future<int?> firstOrdinalOfSurah(String editionId, int surahNumber) async {
    final Database db = await _database.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.ayahTable,
      columns: <String>['ordinal'],
      where: 'edition_id = ? AND surah_number = ?',
      whereArgs: <Object?>[editionId, surahNumber],
      orderBy: 'ordinal ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['ordinal'] as int?;
  }

  Future<void> deleteEdition(String editionId) async {
    final Database db = await _database.database;
    await db.transaction((Transaction txn) async {
      await txn.delete(
        AppDatabase.ayahTable,
        where: 'edition_id = ?',
        whereArgs: <Object?>[editionId],
      );
      await txn.delete(
        AppDatabase.surahsTable,
        where: 'edition_id = ?',
        whereArgs: <Object?>[editionId],
      );
      await txn.delete(
        AppDatabase.editionsTable,
        where: 'id = ?',
        whereArgs: <Object?>[editionId],
      );
    });
  }

  static Map<String, Object?> _toRow(Ayah ayah) => <String, Object?>{
        'id': ayah.id,
        'edition_id': ayah.editionId,
        'ordinal': ayah.ordinal,
        'surah_number': ayah.surahNumber,
        'ayah_number': ayah.ayahNumber,
        'verse_key': ayah.verseKey,
        'surah_name_arabic': ayah.surahNameArabic,
        'surah_name_english': ayah.surahNameEnglish,
        'arabic_text': ayah.arabicText,
        'translation_text': ayah.translationText,
        'transliteration': ayah.transliteration,
        'juz': ayah.juz,
        'page': ayah.page,
        'sajda': ayah.sajda ? 1 : 0,
        'reference': ayah.reference,
        'source': ayah.source,
        'words': _encodeWords(ayah.words),
      };

  /// Words are stored as a JSON array on the ayah row rather than in a table
  /// of their own: they are a value of the ayah, always read with it and never
  /// queried independently, and a separate table would add 77,000 rows and a
  /// join for nothing.
  static String? _encodeWords(List<AyahWord> words) {
    if (words.isEmpty) return null;
    return jsonEncode(<Map<String, Object?>>[
      for (final AyahWord word in words) word.toJson(),
    ]);
  }

  /// Null for an ayah stored before word glosses existed, and for one whose
  /// edition has none. Malformed JSON reads back as no words rather than
  /// failing the read — a gloss is never worth losing the ayah over.
  static List<AyahWord> _decodeWords(Object? value) {
    if (value is! String || value.isEmpty) return const <AyahWord>[];
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return const <AyahWord>[];
    }
    if (decoded is! List) return const <AyahWord>[];
    return <AyahWord>[
      for (final Object? entry in decoded)
        if (entry is Map<String, Object?>) AyahWord.fromJson(entry),
    ];
  }

  static Ayah _fromRow(Map<String, Object?> row) => Ayah(
        id: row['id']! as String,
        editionId: row['edition_id']! as String,
        ordinal: row['ordinal']! as int,
        surahNumber: row['surah_number']! as int,
        ayahNumber: row['ayah_number']! as int,
        surahNameArabic: row['surah_name_arabic'] as String?,
        surahNameEnglish: row['surah_name_english'] as String?,
        arabicText: row['arabic_text'] as String?,
        translationText: row['translation_text'] as String?,
        transliteration: row['transliteration'] as String?,
        juz: row['juz'] as int?,
        page: row['page'] as int?,
        sajda: (row['sajda'] as int?) == 1,
        reference: row['reference'] as String?,
        source: row['source'] as String?,
        words: _decodeWords(row['words']),
      );
}
