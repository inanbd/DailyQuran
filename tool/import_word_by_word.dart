// Builds the app's shared word index from Quran.com API pages.
//
// `tool/fetch_word_by_word.sh` downloads the raw pages; this turns them into
// `assets/data/word_by_word.json`, the file the app loads once and attaches to
// every edition. Word glosses are the same whichever translation is being read,
// so they live in one shared file rather than being duplicated into each
// edition — the same reasoning as the surah index.
//
// Text is copied verbatim. Nothing is glossed, completed or corrected here.
//
// Usage:
//
//   dart run tool/import_word_by_word.dart \
//     --input-dir .dart_tool/quran-wbw \
//     --source-name "Name of the dataset"

import 'dart:convert';
import 'dart:io';

const JsonEncoder _json = JsonEncoder.withIndent('  ');

const String _outputPath = 'assets/data/word_by_word.json';

/// The number of ayat in the standard Kufan numbering, for a coverage report.
const int _standardTotalAyah = 6236;

/// Quran.com marks the ayah-number ornament at the end of a verse as a "word".
/// It is punctuation, not a word of the Qur'an, and is dropped.
const String _endMarker = 'end';

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

  final Directory input = Directory(options.inputDir);
  if (!input.existsSync()) {
    stderr.writeln('Error: input directory not found: ${options.inputDir}');
    return 66;
  }

  final List<File> pages = input
      .listSync()
      .whereType<File>()
      .where((File file) => file.path.endsWith('.json'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  if (pages.isEmpty) {
    stderr.writeln('Error: no JSON pages in ${options.inputDir}.');
    return 65;
  }

  final Map<String, List<Map<String, Object?>>> words =
      <String, List<Map<String, Object?>>>{};
  int droppedMarkers = 0;
  int skippedEmpty = 0;

  for (final File page in pages) {
    final Object? decoded = jsonDecode(await page.readAsString());
    if (decoded is! Map<String, Object?>) continue;
    final Object? verses = decoded['verses'];
    if (verses is! List<Object?>) continue;

    for (final Object? verse in verses) {
      if (verse is! Map<String, Object?>) continue;
      final String? key = _string(verse['verse_key']);
      final Object? rawWords = verse['words'];
      if (key == null || rawWords is! List<Object?>) continue;

      final List<Map<String, Object?>> entries = <Map<String, Object?>>[];
      for (final Object? word in rawWords) {
        if (word is! Map<String, Object?>) continue;
        if (_string(word['char_type_name']) == _endMarker) {
          droppedMarkers++;
          continue;
        }

        final String? arabic =
            _string(word['text_uthmani']) ?? _string(word['text']);
        final String? translation = _nested(word, 'translation');
        final String? transliteration = _nested(word, 'transliteration');
        if (arabic == null && translation == null) continue;

        entries.add(<String, Object?>{
          'arabic': ?arabic,
          'translation': ?translation,
          'transliteration': ?transliteration,
        });
      }

      if (entries.isEmpty) {
        skippedEmpty++;
        continue;
      }
      // A later page for the same ayah replaces an earlier one, so re-running
      // the fetch after a partial download converges rather than duplicating.
      words[key] = entries;
    }
  }

  if (words.isEmpty) {
    stderr.writeln('Error: no words found; nothing to write.');
    return 65;
  }

  final Map<String, Object?> payload = <String, Object?>{
    'schemaVersion': 1,
    'notice': 'Word-by-word glosses: a word-level reading aid for the Arabic, '
        'not a translation of the ayah. Every gloss is copied verbatim from '
        'the source named below.',
    'languageName': options.languageName,
    'languageCode': options.languageCode,
    'source': <String, Object?>{
      'name': options.sourceName,
      if (options.sourceUrl != null) 'url': options.sourceUrl,
      if (options.licence != null) 'licence': options.licence,
      'retrievedAt': DateTime.now().toUtc().toIso8601String(),
    },
    'totalAyah': words.length,
    // Sorted by surah then ayah so the file has a stable, reviewable order.
    'words': <String, Object?>{
      for (final String key in _sortedKeys(words.keys)) key: words[key],
    },
  };

  final File output = File(_outputPath);
  await output.parent.create(recursive: true);
  await output.writeAsString('${_json.convert(payload)}\n');

  final int totalWords =
      words.values.fold(0, (int sum, List<Object?> w) => sum + w.length);
  stdout.writeln(
    'Wrote ${output.path}: ${words.length} ayat, $totalWords words.',
  );
  if (droppedMarkers > 0) {
    stdout.writeln('Dropped $droppedMarkers ayah-number markers.');
  }
  if (skippedEmpty > 0) {
    stdout.writeln('Skipped $skippedEmpty ayat with no words.');
  }
  if (words.length != _standardTotalAyah) {
    stdout.writeln(
      'Note: ${words.length} ayat, not the $_standardTotalAyah of the standard '
      'Kufan numbering. Re-run the fetch if the download was incomplete.',
    );
  }
  return 0;
}

/// Verse keys in mushaf order rather than lexicographic order, so `2:9` comes
/// before `2:10`.
List<String> _sortedKeys(Iterable<String> keys) {
  final List<String> sorted = keys.toList()
    ..sort((String a, String b) {
      final List<int> left = _parseKey(a);
      final List<int> right = _parseKey(b);
      final int bySurah = left[0].compareTo(right[0]);
      return bySurah != 0 ? bySurah : left[1].compareTo(right[1]);
    });
  return sorted;
}

List<int> _parseKey(String key) {
  final List<String> parts = key.split(':');
  if (parts.length != 2) return <int>[0, 0];
  return <int>[int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0];
}

/// Reads `{"translation": {"text": "…"}}`.
String? _nested(Map<String, Object?> word, String field) {
  final Object? value = word[field];
  if (value is! Map<String, Object?>) return null;
  return _string(value['text']);
}

String? _string(Object? value) {
  if (value is! String) return null;
  return value.trim().isEmpty ? null : value;
}

class _UsageError implements Exception {
  _UsageError(this.message);

  final String message;
}

class _Options {
  _Options({
    required this.inputDir,
    required this.sourceName,
    required this.languageName,
    required this.languageCode,
    this.sourceUrl,
    this.licence,
    this.showHelp = false,
  });

  factory _Options.parse(List<String> arguments) {
    if (arguments.contains('--help') || arguments.contains('-h')) {
      return _Options(
        inputDir: '',
        sourceName: '',
        languageName: 'English',
        languageCode: 'en',
        showHelp: true,
      );
    }

    final Map<String, String> values = <String, String>{};
    for (int i = 0; i < arguments.length; i++) {
      final String argument = arguments[i];
      if (!argument.startsWith('--')) {
        throw _UsageError('Unexpected argument "$argument".');
      }
      final String name = argument.substring(2);
      if (i + 1 >= arguments.length) {
        throw _UsageError('Missing value for --$name.');
      }
      values[name] = arguments[++i];
    }

    for (final String required in <String>['input-dir', 'source-name']) {
      if ((values[required] ?? '').isEmpty) {
        throw _UsageError('--$required is required.');
      }
    }

    final String languageName = values['language-name'] ?? 'english';
    return _Options(
      inputDir: values['input-dir']!,
      sourceName: values['source-name']!,
      sourceUrl: values['source-url'],
      licence: values['licence'],
      // The fetch script passes the API's own language name, which is
      // lower-case; capitalise it for display.
      languageName: languageName.isEmpty
          ? 'English'
          : languageName[0].toUpperCase() + languageName.substring(1),
      languageCode: values['language-code'] ?? 'en',
    );
  }

  final String inputDir;
  final String sourceName;
  final String? sourceUrl;
  final String? licence;
  final String languageName;
  final String languageCode;
  final bool showHelp;
}

const String _usage = '''
Build the shared word index from downloaded Quran.com API pages.

Required:
  --input-dir <path>      Directory of raw API pages (see
                          tool/fetch_word_by_word.sh).
  --source-name <name>    Attribution shown in the app. Never left blank.

Optional:
  --source-url <url>      Link to the source.
  --licence <name>        Licence the glosses are distributed under.
  --language-name <name>  Language of the glosses. Default: english.
  --language-code <code>  BCP-47 code for them. Default: en.
  -h, --help              Show this message.

Writes $_outputPath. Ayah-number ornaments the API returns as words are
dropped; everything else is copied verbatim.
''';
