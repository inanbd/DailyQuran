// Imports a Qur'an dataset into the app's asset format.
//
// The app reads editions from `assets/data/editions/<slug>.json`, in the shape
// documented in `lib/data/content/content_schema.dart`. This tool converts a
// third-party dataset into that shape and records where it came from, so
// attribution travels with the text.
//
// It never invents, rewrites, completes or reformats Qur'an text. Every field
// is copied verbatim from the input; entries with no text at all are reported
// and skipped rather than filled in.
//
// Two input shapes are supported:
//
//   * flat    — one array of ayat, each carrying its own surah and ayah number
//               (`--array-path`).
//   * grouped — an array of surahs, each holding its own array of verses
//               (`--group-path` + `--verses-key`). This is what most published
//               Qur'an datasets look like.
//
// Usage:
//
//   dart run tool/import_quran.dart \
//     --input path/to/quran_en.json \
//     --edition saheeh_international \
//     --source-name "Name of the dataset" \
//     --group-path "" --verses-key verses \
//     --map ayah=id --map arabic=text --map translation=translation
//
// Run with --help for the full list of options.

import 'dart:convert';
import 'dart:io';

const JsonEncoder _json = JsonEncoder.withIndent('  ');

const String _catalogPath = 'assets/data/catalog.json';
const String _surahIndexPath = 'assets/data/surahs.json';
const String _editionsDir = 'assets/data/editions';

/// The number of ayat in the standard Kufan numbering. Used only to warn when
/// an import does not look like a complete Qur'an; nothing is rejected for it,
/// because other numberings exist and the app trusts what it is given.
const int _standardTotalAyah = 6236;

/// Ayah fields the app understands, and the input keys they default to.
const Map<String, String> _defaultMapping = <String, String>{
  'surah': 'surah',
  'ayah': 'ayah',
  'arabic': 'arabic',
  'translation': 'translation',
  'transliteration': 'transliteration',
  'juz': 'juz',
  'page': 'page',
  'sajda': 'sajda',
  'reference': 'reference',
};

/// Fields of the surah a grouped dataset nests its verses under.
const Map<String, String> _defaultGroupMapping = <String, String>{
  'number': 'id',
  'nameArabic': 'name',
  'nameTransliterated': 'transliteration',
  'nameEnglish': 'translation',
};

Future<int> main(List<String> arguments) async {
  final _Options options;
  try {
    options = _Options.parse(arguments);
  } on _UsageError catch (error) {
    stderr.writeln('Error: ${error.message}\n');
    stderr.writeln(_usage);
    return 64;
  }

  if (options.showHelp) {
    stdout.writeln(_usage);
    return 0;
  }

  final File input = File(options.inputPath);
  if (!input.existsSync()) {
    stderr.writeln('Error: input file not found: ${options.inputPath}');
    return 66;
  }

  final Object? decoded = jsonDecode(await input.readAsString());

  // The shared surah index supplies names and, when the dataset carries no
  // citation of its own, the surah name a reference is built from. It is
  // reference data that ships with the app, never text.
  final Map<int, _SurahName> surahNames = await _readSurahIndex();

  // A second dataset in the same shape, joined on (surah, ayah). This is how
  // transliterations are published: as their own file.
  final Map<String, String> extra = await _readJoinFile(options);

  final List<_Entry> entries = _readEntries(decoded, options);
  if (entries.isEmpty) {
    stderr.writeln('Error: no entries found in ${options.inputPath}.');
    stderr.writeln(
      'Hint: pass --array-path for a flat dataset, or --group-path and '
      '--verses-key for one that nests verses under each surah.',
    );
    return 65;
  }

  final List<Map<String, Object?>> ayat = <Map<String, Object?>>[];
  final Set<String> seen = <String>{};
  int skipped = 0;
  int duplicates = 0;

  for (final _Entry entry in entries) {
    final Map<String, Object?> json = entry.json;
    final String? arabic = _readString(json, options.mapping['arabic']);
    final String? translation =
        _readString(json, options.mapping['translation']);

    if (arabic == null && translation == null) {
      // An entry with no text is a gap in the source, not something to fill in.
      stderr.writeln(
        'Skipping ${entry.surahNumber}:${_readInt(json, options.mapping['ayah'])}'
        ': no Arabic or translation text.',
      );
      skipped++;
      continue;
    }

    final int? surah =
        entry.surahNumber ?? _readInt(json, options.mapping['surah']);
    final int? ayah = _readInt(json, options.mapping['ayah']);
    if (surah == null || ayah == null) {
      stderr.writeln(
        'Skipping an entry with no surah or ayah number. Map them with '
        '--map surah=<path> and --map ayah=<path>.',
      );
      skipped++;
      continue;
    }

    final String verseKey = '$surah:$ayah';
    if (!seen.add(verseKey)) {
      // Two entries claiming the same ayah means the mapping is wrong, or the
      // dataset repeats itself. Either way the second is not written.
      stderr.writeln('Skipping duplicate entry for $verseKey.');
      duplicates++;
      continue;
    }

    final _SurahName? name = surahNames[surah];
    ayat.add(<String, Object?>{
      'surah': surah,
      'ayah': ayah,
      'surahNameArabic': entry.surahNameArabic ?? name?.arabic,
      'surahNameEnglish': entry.surahNameEnglish ?? name?.english,
      'arabic': arabic,
      'translation': translation,
      'transliteration':
          _readString(json, options.mapping['transliteration']) ??
              extra[verseKey],
      'juz': _readInt(json, options.mapping['juz']),
      'page': _readInt(json, options.mapping['page']),
      if (_readBool(json, options.mapping['sajda'])) 'sajda': true,
      'reference': _readString(json, options.mapping['reference']) ??
          _buildReference(options.referenceTemplate, name, surah, ayah),
    }..removeWhere((String key, Object? value) => value == null));
  }

  if (ayat.isEmpty) {
    stderr.writeln('Error: every entry was skipped; nothing to write.');
    return 65;
  }

  final Map<String, Object?> source = <String, Object?>{
    'name': options.sourceName,
    if (options.sourceUrl != null) 'url': options.sourceUrl,
    if (options.translator != null) 'translator': options.translator,
    if (options.licence != null) 'licence': options.licence,
    'retrievedAt': DateTime.now().toUtc().toIso8601String(),
  };

  final Map<String, Object?> payload = <String, Object?>{
    'schemaVersion': 1,
    'editionId': options.editionId,
    'verification': options.verification,
    'source': source,
    // Surahs are deliberately not written for a verified edition: names and
    // lengths are the same for every complete Qur'an, so the edition inherits
    // the shared index in assets/data/surahs.json. A fixture, whose sections
    // are not the Qur'an's, carries its own.
    if (options.verification != 'verified') 'surahs': _deriveSurahs(ayat),
    'ayat': ayat,
  };

  final String slug = await _updateCatalog(options, ayat.length, source);
  final File output = File('$_editionsDir/$slug.json');
  await output.parent.create(recursive: true);
  await output.writeAsString('${_json.convert(payload)}\n');

  stdout.writeln('Imported ${ayat.length} ayat into ${output.path}');
  if (skipped > 0) stdout.writeln('Skipped $skipped entries without text.');
  if (duplicates > 0) stdout.writeln('Skipped $duplicates duplicate entries.');
  if (options.verification == 'verified' &&
      ayat.length != _standardTotalAyah) {
    stdout.writeln(
      'Note: ${ayat.length} ayat, not the $_standardTotalAyah of the standard '
      'Kufan numbering. Numbering varies between editions; check this is the '
      'count you expected.',
    );
  }
  stdout.writeln('Updated $_catalogPath (totalAyah and source).');
  stdout.writeln(
    'Run `flutter pub get && flutter run` to pick up the new edition.',
  );
  return 0;
}

/// One entry to import, with whatever its enclosing surah told us.
class _Entry {
  const _Entry({
    required this.json,
    this.surahNumber,
    this.surahNameArabic,
    this.surahNameEnglish,
  });

  final Map<String, Object?> json;

  /// Set when the dataset groups verses under a surah, so the number does not
  /// have to be repeated on every verse.
  final int? surahNumber;
  final String? surahNameArabic;
  final String? surahNameEnglish;
}

/// Flattens the dataset into entries, in reading order.
List<_Entry> _readEntries(Object? document, _Options options) {
  if (options.groupPath == null) {
    return <_Entry>[
      for (final Object? entry in _locateArray(document, options.arrayPath))
        if (entry is Map<String, Object?>) _Entry(json: entry),
    ];
  }

  final List<_Entry> entries = <_Entry>[];
  for (final Object? group in _locateArray(document, options.groupPath)) {
    if (group is! Map<String, Object?>) continue;
    final int? number = _readInt(group, options.groupMapping['number']);
    final String? nameArabic =
        _readString(group, options.groupMapping['nameArabic']);
    final String? nameEnglish =
        _readString(group, options.groupMapping['nameEnglish']);
    final Object? verses = group[options.versesKey];
    if (verses is! List<Object?>) continue;
    for (final Object? verse in verses) {
      if (verse is! Map<String, Object?>) continue;
      entries.add(
        _Entry(
          json: verse,
          surahNumber: number,
          surahNameArabic: nameArabic,
          surahNameEnglish: nameEnglish,
        ),
      );
    }
  }
  return entries;
}

/// Reads a second dataset — normally a transliteration — into a lookup keyed
/// by verse key, so it can be joined onto the entries being imported.
Future<Map<String, String>> _readJoinFile(_Options options) async {
  final String? path = options.joinPath;
  if (path == null) return const <String, String>{};

  final File file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Warning: --join-input "$path" not found; skipping.');
    return const <String, String>{};
  }

  final Object? decoded = jsonDecode(await file.readAsString());
  final Map<String, String> index = <String, String>{};
  for (final _Entry entry in _readEntries(decoded, options)) {
    final int? surah =
        entry.surahNumber ?? _readInt(entry.json, options.mapping['surah']);
    final int? ayah = _readInt(entry.json, options.mapping['ayah']);
    final String? value = _readString(entry.json, options.joinField);
    if (surah == null || ayah == null || value == null) continue;
    index['$surah:$ayah'] = value;
  }
  if (index.isEmpty) {
    stderr.writeln('Warning: --join-input "$path" produced no values.');
  }
  return index;
}

/// A surah's names, from the index that ships with the app.
class _SurahName {
  const _SurahName({required this.arabic, required this.english});

  final String? arabic;
  final String? english;
}

/// Reads the shared surah index. Returns an empty map if it is missing, in
/// which case surah names come only from the dataset.
Future<Map<int, _SurahName>> _readSurahIndex() async {
  final File file = File(_surahIndexPath);
  if (!file.existsSync()) {
    stderr.writeln('Warning: $_surahIndexPath not found; surah names will '
        'come only from the dataset.');
    return const <int, _SurahName>{};
  }
  final Object? decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, Object?>) return const <int, _SurahName>{};
  final Object? surahs = decoded['surahs'];
  if (surahs is! List<Object?>) return const <int, _SurahName>{};

  final Map<int, _SurahName> index = <int, _SurahName>{};
  for (final Object? entry in surahs) {
    if (entry is! Map<String, Object?>) continue;
    final int? number = _readInt(entry, 'number');
    if (number == null) continue;
    index[number] = _SurahName(
      arabic: _readString(entry, 'nameArabic'),
      english: _readString(entry, 'nameTransliterated') ??
          _readString(entry, 'nameEnglish'),
    );
  }
  return index;
}

/// Rewrites the catalog entry for this edition, and returns its slug.
Future<String> _updateCatalog(
  _Options options,
  int total,
  Map<String, Object?> source,
) async {
  final File catalogFile = File(_catalogPath);
  if (!catalogFile.existsSync()) {
    throw StateError('Catalog not found at $_catalogPath.');
  }

  final Map<String, Object?> catalog =
      jsonDecode(await catalogFile.readAsString()) as Map<String, Object?>;
  final List<Object?> editions =
      (catalog['editions'] as List<Object?>?) ?? <Object?>[];

  Map<String, Object?>? entry;
  for (final Object? candidate in editions) {
    if (candidate is Map<String, Object?> &&
        candidate['id'] == options.editionId) {
      entry = candidate;
      break;
    }
  }

  if (entry == null) {
    // An edition the catalog has never heard of is added with what we know;
    // the title and description can be filled in by hand afterwards.
    entry = <String, Object?>{
      'id': options.editionId,
      'slug': options.editionId,
      'titleEnglish': options.editionId,
      'titleArabic': '',
      'translator': '',
      'description': '',
      if (options.verification == 'verified') 'progressScope': 'quran',
    };
    editions.add(entry);
    catalog['editions'] = editions;
    stdout.writeln(
      'Note: "${options.editionId}" was not in the catalog and has been '
      'added. Fill in its title, translator and description.',
    );
  }

  entry['totalAyah'] = total;
  entry['verification'] = options.verification;
  entry['source'] = source;

  await catalogFile.writeAsString('${_json.convert(catalog)}\n');

  return (entry['slug'] as String?) ?? options.editionId;
}

/// Builds a citation like "Al-Baqarah 2:255" from a template.
///
/// This is a reference, not Qur'an text: it is assembled only from the surah
/// index that ships with the app and the numbering the source published.
String? _buildReference(
  String? template,
  _SurahName? name,
  int surah,
  int ayah,
) {
  if (template == null || template.isEmpty) return null;
  return template
      .replaceAll('{surah}', '$surah')
      .replaceAll('{ayah}', '$ayah')
      .replaceAll('{surahName}', name?.english ?? 'Surah $surah');
}

/// Builds a surah list from whatever surah metadata the entries carry. Used
/// only for fixtures; verified editions inherit the shared index.
List<Map<String, Object?>> _deriveSurahs(List<Map<String, Object?>> ayat) {
  final Map<int, Map<String, Object?>> surahs = <int, Map<String, Object?>>{};
  for (final Map<String, Object?> entry in ayat) {
    final Object? number = entry['surah'];
    if (number is! int) continue;
    final Map<String, Object?> surah = surahs.putIfAbsent(
      number,
      () => <String, Object?>{
        'number': number,
        'nameArabic': entry['surahNameArabic'] ?? '',
        'nameTransliterated': '',
        'nameEnglish': entry['surahNameEnglish'] ?? '',
        'ayahCount': 0,
        'revelationPlace': 'unknown',
      },
    );
    surah['ayahCount'] = (surah['ayahCount']! as int) + 1;
  }
  final List<Map<String, Object?>> result = surahs.values.toList()
    ..sort(
      (Map<String, Object?> a, Map<String, Object?> b) =>
          (a['number']! as int).compareTo(b['number']! as int),
    );
  return result;
}

/// Finds an array, either at the document root or under [path]
/// (dot-separated). An empty [path] means the root.
List<Object?> _locateArray(Object? document, String? path) {
  if (path == null || path.isEmpty) {
    if (document is List<Object?>) return document;
    if (document is Map<String, Object?>) {
      // Common shapes: {"ayat": [...]}, {"verses": [...]}, {"data": [...]}.
      for (final String key in <String>[
        'ayat',
        'ayahs',
        'verses',
        'surahs',
        'chapters',
        'data',
        'items',
      ]) {
        final Object? value = document[key];
        if (value is List<Object?>) return value;
      }
    }
    return const <Object?>[];
  }

  Object? cursor = document;
  for (final String segment in path.split('.')) {
    if (cursor is! Map<String, Object?>) return const <Object?>[];
    cursor = cursor[segment];
  }
  return cursor is List<Object?> ? cursor : const <Object?>[];
}

/// Reads a possibly nested value, e.g. `english.text`.
Object? _readPath(Map<String, Object?> entry, String? path) {
  if (path == null || path.isEmpty) return null;
  Object? cursor = entry;
  for (final String segment in path.split('.')) {
    if (cursor is! Map<String, Object?>) return null;
    cursor = cursor[segment];
  }
  return cursor;
}

String? _readString(Map<String, Object?> entry, String? path) {
  final Object? value = _readPath(entry, path);
  if (value == null) return null;
  final String text = value is String ? value : value.toString();
  return text.trim().isEmpty ? null : text;
}

int? _readInt(Map<String, Object?> entry, String? path) {
  final Object? value = _readPath(entry, path);
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// True only when the source explicitly says so. A sajda is never inferred.
bool _readBool(Map<String, Object?> entry, String? path) {
  final Object? value = _readPath(entry, path);
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final String normalised = value.trim().toLowerCase();
    return normalised == 'true' || normalised == 'yes' || normalised == '1';
  }
  return false;
}

class _UsageError implements Exception {
  _UsageError(this.message);

  final String message;
}

class _Options {
  _Options({
    required this.inputPath,
    required this.editionId,
    required this.sourceName,
    required this.mapping,
    required this.groupMapping,
    required this.verification,
    required this.versesKey,
    required this.joinField,
    this.sourceUrl,
    this.translator,
    this.licence,
    this.arrayPath,
    this.groupPath,
    this.joinPath,
    this.referenceTemplate,
    this.showHelp = false,
  });

  factory _Options.parse(List<String> arguments) {
    if (arguments.contains('--help') || arguments.contains('-h')) {
      return _Options(
        inputPath: '',
        editionId: '',
        sourceName: '',
        mapping: _defaultMapping,
        groupMapping: _defaultGroupMapping,
        verification: 'verified',
        versesKey: 'verses',
        joinField: 'transliteration',
        showHelp: true,
      );
    }

    final Map<String, String> values = <String, String>{};
    final Map<String, String> mapping = Map<String, String>.of(_defaultMapping);
    final Map<String, String> groupMapping =
        Map<String, String>.of(_defaultGroupMapping);
    bool fixture = false;

    for (int i = 0; i < arguments.length; i++) {
      final String argument = arguments[i];
      if (argument == '--fixture') {
        fixture = true;
        continue;
      }
      if (!argument.startsWith('--')) {
        throw _UsageError('Unexpected argument "$argument".');
      }
      final String name = argument.substring(2);
      if (i + 1 >= arguments.length) {
        throw _UsageError('Missing value for --$name.');
      }
      final String value = arguments[++i];

      if (name == 'map' || name == 'group-map') {
        final bool isGroup = name == 'group-map';
        final Map<String, String> target = isGroup ? groupMapping : mapping;
        final Map<String, String> known =
            isGroup ? _defaultGroupMapping : _defaultMapping;

        final int split = value.indexOf('=');
        if (split <= 0) {
          throw _UsageError('--$name expects field=path, got "$value".');
        }
        final String field = value.substring(0, split);
        if (!known.containsKey(field)) {
          throw _UsageError(
            'Unknown --$name field "$field". Known fields: '
            '${known.keys.join(', ')}.',
          );
        }
        target[field] = value.substring(split + 1);
        continue;
      }
      values[name] = value;
    }

    for (final String required in <String>[
      'input',
      'edition',
      'source-name',
    ]) {
      if ((values[required] ?? '').isEmpty) {
        throw _UsageError('--$required is required.');
      }
    }

    return _Options(
      inputPath: values['input']!,
      editionId: values['edition']!,
      sourceName: values['source-name']!,
      sourceUrl: values['source-url'],
      translator: values['translator'],
      licence: values['licence'],
      arrayPath: values['array-path'],
      groupPath: values['group-path'],
      versesKey: values['verses-key'] ?? 'verses',
      joinPath: values['join-input'],
      joinField: values['join-field'] ?? 'transliteration',
      referenceTemplate: values['reference-template'],
      mapping: mapping,
      groupMapping: groupMapping,
      verification: fixture ? 'development_fixture' : 'verified',
    );
  }

  final String inputPath;
  final String editionId;
  final String sourceName;
  final String? sourceUrl;
  final String? translator;
  final String? licence;

  /// Dot path to a flat array of ayat.
  final String? arrayPath;

  /// Dot path to an array of surahs, each nesting its own verses. An empty
  /// string means the root array.
  final String? groupPath;

  /// Key holding the verses inside each group.
  final String versesKey;

  /// A second dataset joined on (surah, ayah) — normally a transliteration.
  final String? joinPath;

  /// Field read from each entry of the join file.
  final String joinField;

  /// Citation template, e.g. "{surahName} {surah}:{ayah}".
  final String? referenceTemplate;

  final Map<String, String> mapping;
  final Map<String, String> groupMapping;
  final String verification;
  final bool showHelp;
}

const String _usage = '''
Import a Qur'an dataset into the app's asset format.

Required:
  --input <path>          JSON file to read.
  --edition <id>          Catalog id to import into, e.g. saheeh_international.
  --source-name <name>    Attribution shown in the app. Never left blank.

Input shape (choose one):
  --array-path <path>     Dot path to a flat array of ayat. Omitted, the root
                          array (or ayat/ayahs/verses/data/items) is used.
  --group-path <path>     Dot path to an array of surahs that nest their own
                          verses. Use "" for the root array.
  --verses-key <key>      Key holding the verses inside each group.
                          Default: verses.

Optional:
  --source-url <url>      Link to the dataset or publisher.
  --translator <name>     Credited translator.
  --licence <name>        Licence the dataset is distributed under.
  --map <field>=<path>    Map an app field to an input path. Repeatable.
                          Paths may be nested, e.g. translation=text.en.
  --group-map <f>=<p>     Map a surah field to a path inside each group.
                          Repeatable.
  --join-input <path>     A second dataset in the same shape, joined on
                          (surah, ayah). This is how transliterations are
                          usually published.
  --join-field <path>     Field read from each entry of --join-input.
                          Default: transliteration.
  --reference-template <t>
                          Citation to use when entries carry none, e.g.
                          "{surahName} {surah}:{ayah}". Placeholders:
                          {surah}, {ayah}, {surahName}. Assembled only from the
                          bundled surah index and the source's own numbering.
  --fixture               Mark the import as development data rather than
                          verified content.
  -h, --help              Show this message.

App fields available to --map:
  surah, ayah, arabic, translation, transliteration, juz, page, sajda,
  reference

Surah fields available to --group-map:
  number, nameArabic, nameTransliterated, nameEnglish

Text is copied verbatim. Entries with neither Arabic nor a translation are
reported and skipped, and duplicate verse keys are reported and skipped.
''';
