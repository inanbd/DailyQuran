import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/entities/quran_edition.dart';
import 'package:flutter_test/flutter_test.dart';

/// How a translation's language is named in the lists the reader chooses from.
void main() {
  QuranEdition edition({required String name, String? native}) => QuranEdition(
        id: 'e',
        slug: 'e',
        titleEnglish: 'A translation',
        titleArabic: '',
        translator: 'A translator',
        description: '',
        languageName: name,
        languageNativeName: native,
        totalAyah: 6236,
        source: const ContentSource(name: 'A source'),
        verification: ContentVerification.verified,
      );

  test('a language with a native name shows both', () {
    expect(
      edition(name: 'French', native: 'Français').languageLabel,
      contains('French ('),
    );
    expect(
      edition(name: 'French', native: 'Français').languageLabel,
      contains('Français'),
    );
  });

  test('a language with no native name shows only its English name', () {
    expect(edition(name: 'English').languageLabel, 'English');
  });

  test('a native name identical to the English one is not repeated', () {
    expect(edition(name: 'English', native: 'English').languageLabel, 'English');
  });

  test('an empty native name is treated as absent', () {
    expect(edition(name: 'English', native: '').languageLabel, 'English');
  });

  test('a right-to-left native name is isolated so the brackets stay put', () {
    // Without the isolate, bidi resolution pulls the direction-neutral closing
    // bracket to the wrong side of the Arabic and the label reads `Urdu )اردو(`
    // on screen. The isolate must sit inside the brackets, wrapping only the
    // native name.
    final String label = edition(name: 'Urdu', native: 'اردو').languageLabel;
    expect(label, startsWith('Urdu ('));
    expect(label, endsWith(')'));
    expect(label.codeUnits, contains(0x2068));
    expect(label.codeUnits, contains(0x2069));
    expect(
      label.indexOf(String.fromCharCode(0x2068)),
      lessThan(label.indexOf('اردو')),
    );
    expect(
      label.indexOf(String.fromCharCode(0x2069)),
      greaterThan(label.indexOf('اردو')),
    );
  });
}
