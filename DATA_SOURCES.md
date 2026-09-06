# Qur'an data sources

This file documents where the app's text comes from, what shape it must be in,
and what to check before importing an edition.

## The rule this project holds to

Qur'an text and translations are never generated, paraphrased, completed,
corrected or reformatted by this application or by any tool in this repository.
They are copied verbatim from a dataset you choose, and they always travel with
an attribution record.

If a dataset has no transliteration for an entry, the app shows none. If it does
not mark an ayah as a place of prostration, the app does not say it is one. Gaps
in a source stay gaps.

## What ships in this repository

| Edition | Status |
|---|---|
| `dev_sample` — "Development Sample" | **Development fixture. Not the Qur'an.** Placeholder prose written for this repository to exercise layout, typography and RTL rendering. |
| `saheeh_international` | Uthmani Arabic + Saheeh International English + English transliteration, imported from `quran-json` under CC BY-SA 4.0. |
| `arabic_uthmani`, `maududi`, `hamidullah`, `garcia`, `kuliev`, `muhiuddin_khan` | Bibliographic metadata only. No text. Each shows a "Dataset not installed" state until imported — one command each, see below. |

Also bundled, and **not** Qur'an text:

| File | What it is |
|---|---|
| `assets/data/surahs.json` | The surah index: names, ayah counts and Meccan/Medinan classification for all 114 surahs, in the standard Kufan numbering. Reference data. Its counts sum to 6,236, which the test suite asserts. |

The fixture is marked `"verification": "development_fixture"` in the catalog.
The app surfaces that on the Today screen, on the edition screen, on the library
card and under **Settings → Qur'an sources**. `flutter test
test/data/bundled_assets_test.dart` fails if that labelling is ever lost, if the
fixture's placeholder sections start borrowing real surah names, or if an
edition ships text without real attribution.

## Choosing a dataset

Before importing, check that the dataset:

1. **Names its provenance.** Which text is the Arabic from — Uthmani, Imlaei,
   which encyclopaedia or mushaf? Who produced the translation?
2. **Has a licence you can comply with.** Many Qur'an datasets circulating on
   code-hosting sites carry no licence file at all, which means no permission to
   redistribute. Shipping text inside a published app is redistribution.
3. **Uses a numbering you can name.** The standard Kufan numbering gives 6,236
   ayat; other traditions differ. The importer warns when a verified import is
   not 6,236 entries rather than rejecting it, and the app measures progress
   against what is actually installed.
4. **Keeps Arabic and translation aligned.** Spot-check entries at the start,
   middle and end after importing. `test/features/real_dataset_smoke_test.dart`
   does exactly this, and additionally checks that Ayat al-Kursi (2:255) lands
   at reading position 262.
5. **Marks prostrations honestly**, where it marks them at all. The app shows
   the marking verbatim and never infers one.

Translators generally need to be credited by name. Record them with
`--source-name` and `--translator` so the app can show them.

## The data contract

Three files, all plain JSON. This is the whole contract — anything that can emit
these shapes can back the app.

### `assets/data/catalog.json`

```jsonc
{
  "schemaVersion": 1,
  "editions": [
    {
      "id": "saheeh_international",   // stable key; preferences point at it
      "slug": "saheeh_international", // file name under assets/data/editions/
      "titleEnglish": "Saheeh International",
      "titleArabic": "القرآن الكريم",
      "translator": "Umm Muhammad (Saheeh International)",
      "description": "…",
      "languageName": "English",      // shown in the library
      "languageCode": "en-US",        // picks the text-to-speech voice
      "languageDirection": "rtl",     // optional; omit for left-to-right
      "totalAyah": 6236,
      "progressScope": "quran",       // see below
      "verification": "verified",     // or "development_fixture"
      "source": {
        "name": "…",                  // required; shown as attribution
        "url": "https://…",
        "translator": "…",
        "licence": "…",
        "retrievedAt": "2026-09-06T00:00:00Z"
      }
    }
  ]
}
```

**`progressScope` is the important one.** Every complete edition of the Qur'an
should declare `"quran"`, so that reading progress and saved ayat are shared:
changing translation then keeps the reader's place instead of restarting them.
Omit it only for something that is *not* the Qur'an — the development fixture —
so its progress can never be mistaken for progress through the Qur'an.

An edition is readable when `assets/data/editions/<slug>.json` exists. Catalog
entries without one are listed but not startable.

### `assets/data/editions/<slug>.json`

```jsonc
{
  "schemaVersion": 1,
  "editionId": "saheeh_international",
  "verification": "verified",
  "source": { "name": "…" },
  // Omitted by a complete edition, which inherits assets/data/surahs.json.
  // Present only for an edition whose sections are not the Qur'an's.
  "surahs": [ /* see below */ ],
  "ayat": [
    {
      "surah": 2,
      "ayah": 255,
      "surahNameArabic": "البقرة",
      "surahNameEnglish": "Al-Baqarah",
      "arabic": "…",                // verbatim
      "translation": "…",           // verbatim
      "transliteration": "…",       // verbatim, optional
      "juz": 3,                     // optional
      "page": 42,                   // optional
      "sajda": true,                // only where the source says so
      "reference": "Al-Baqarah 2:255"
    }
  ]
}
```

### `assets/data/surahs.json`

```jsonc
{
  "schemaVersion": 1,
  "totalAyah": 6236,
  "surahs": [
    {
      "number": 1,
      "nameArabic": "الفاتحة",
      "nameTransliterated": "Al-Fatihah",
      "nameEnglish": "The Opener",
      "ayahCount": 7,
      "revelationPlace": "meccan"    // or "medinan", or "unknown"
    }
  ]
}
```

Notes:

- **Array order is reading order.** The app assigns `ordinal` 1..N from the
  array position; `surah`/`ayah` are the identity the source published, and
  together they form the verse key (`2:255`) that progress and favourites are
  stored under. Verse keys must be unique within an edition.
- **Every entry needs at least one of `arabic` or `translation`.** Entries with
  neither are skipped by the importer and reported.
- **Whitespace-only strings are treated as absent**, so a source that uses `""`
  for missing fields does not produce empty blocks in the reader.
- **A complete edition should omit `surahs`.** Surah names and lengths are the
  same for every edition of the Qur'an, so they live once in the shared index
  rather than being duplicated into every translation.

## Recipe: the `quran-json` dataset

[`risan/quran-json`](https://github.com/risan/quran-json) is a clean, complete
and — importantly — properly licensed dataset: the Uthmani text from
[The Noble Qur'an Encyclopedia](https://quranenc.com/), with translations and an
English transliteration from [Tanzil.net](https://tanzil.net/), published under
**CC BY-SA 4.0**.

That licence lets you redistribute it, including inside an app you ship,
provided you credit it and license your adaptations of it under the same terms.
The converted file the importer writes is such an adaptation, so
`assets/data/editions/<slug>.json` is CC BY-SA 4.0 — the app code alongside it
is not affected. The importer records the attribution in the catalog, and the
app shows it under **Settings → Qur'an sources**.

### One command

```bash
./tool/fetch_quran_json.sh saheeh_international   # or: all
```

That clones the dataset into `.dart_tool/quran-json` (git-ignored, cached
between runs) and imports it. Available editions:

| Edition | Translator | Dataset file |
|---|---|---|
| `arabic_uthmani` | — (Arabic only) | `dist/quran.json` |
| `saheeh_international` | Umm Muhammad (Saheeh International) | `dist/quran_en.json` |
| `maududi` | Abul A'la Maududi (Urdu) | `dist/quran_ur.json` |
| `hamidullah` | Muhammad Hamidullah (French) | `dist/quran_fr.json` |
| `garcia` | Muhammad Isa García (Spanish) | `dist/quran_es.json` |
| `kuliev` | Elmir Kuliev (Russian) | `dist/quran_ru.json` |
| `muhiuddin_khan` | Muhiuddin Khan (Bengali) | `dist/quran_bn.json` |

The English transliteration in `dist/quran_transliteration.json` is joined onto
every one of them, so the **Show transliteration** setting has something to
show whichever translation you read.

Then:

```bash
flutter test test/data/bundled_assets_test.dart          # structure and labelling
flutter test test/features/real_dataset_smoke_test.dart  # ordering and content
flutter run
```

### The same thing by hand

The script is a thin wrapper. The underlying call, for the French translation:

```bash
dart run tool/import_quran.dart \
  --input .dart_tool/quran-json/dist/quran_fr.json \
  --edition hamidullah \
  --source-name "quran-json (Risan Bagja Pradana); Uthmani text from The Noble Qur'an Encyclopedia, translations from Tanzil.net" \
  --source-url "https://github.com/risan/quran-json" \
  --licence "CC BY-SA 4.0" \
  --translator "Muhammad Hamidullah" \
  --group-path "" \
  --verses-key verses \
  --group-map number=id \
  --group-map nameArabic=name \
  --group-map nameEnglish=transliteration \
  --map ayah=id \
  --map arabic=text \
  --map translation=translation \
  --join-input .dart_tool/quran-json/dist/quran_transliteration.json \
  --join-field transliteration \
  --reference-template "{surahName} {surah}:{ayah}"
```

Three flags earn their keep on this dataset:

- `--group-path ""` with `--verses-key verses` — the dataset is an array of 114
  surahs, each holding its own verses, rather than one flat list of ayat. The
  surah number and names come from the group, so they do not have to be repeated
  on every verse.
- `--join-input` — the transliteration is published as its own file. This joins
  it on (surah, ayah). It is a merge of two verbatim sources, not a
  transliteration the tool produces.
- `--reference-template` — the dataset carries no citation string. The template
  builds one from the bundled surah index and the numbering the source
  published. It assembles a *reference*, never text.

The dataset marks no prostrations and carries no juz' or page numbers, so the
app shows none for these imports — which is correct; it never infers them.

## Adding an edition the catalog does not know about

`--edition <id>` for an unknown id adds a stub entry to the catalog, with a
shared `progressScope` if the import is verified, and tells you to fill in the
title, translator and description by hand. The importer never invents those.
