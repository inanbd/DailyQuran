#!/usr/bin/env bash
#
# Imports an edition from the `quran-json` dataset
# (https://github.com/risan/quran-json): the Uthmani Arabic text from The Noble
# Qur'an Encyclopedia, with translations and an English transliteration sourced
# from Tanzil.net.
#
#   ./tool/fetch_quran_json.sh saheeh_international
#   ./tool/fetch_quran_json.sh all
#
# LICENCE: the dataset is published under CC BY-SA 4.0. You may redistribute it,
# including inside an app you ship, provided you credit it and license your own
# adaptations of it under the same terms. The importer records the attribution
# in assets/data/catalog.json, and the app shows it under
# Settings -> Qur'an sources. Read DATA_SOURCES.md before you release a build
# containing it.

set -euo pipefail

DATASET_REF="master"
DATASET_REPO="https://github.com/risan/quran-json.git"
CACHE_DIR="${QURAN_JSON_CACHE:-.dart_tool/quran-json}"
DATASET_URL="https://github.com/risan/quran-json"
DATASET_LICENCE="CC BY-SA 4.0"
SOURCE_NAME="quran-json (Risan Bagja Pradana); Uthmani text from The Noble Qur'an Encyclopedia, translations from Tanzil.net"

# The transliteration lives in its own file and is joined onto every edition.
TRANSLITERATION="dist/quran_transliteration.json"

# edition-id | dataset file | translator credited by the dataset
CATALOG="
arabic_uthmani|dist/quran.json|
saheeh_international|dist/quran_en.json|Umm Muhammad (Saheeh International)
maududi|dist/quran_ur.json|Abul A'la Maududi
hamidullah|dist/quran_fr.json|Muhammad Hamidullah
garcia|dist/quran_es.json|Muhammad Isa García
kuliev|dist/quran_ru.json|Elmir Kuliev
muhiuddin_khan|dist/quran_bn.json|Muhiuddin Khan
"

usage() {
  echo "Usage: $0 <edition-id|all>"
  echo
  echo "Editions:"
  while IFS='|' read -r id file translator; do
    if [ -n "$id" ]; then
      printf '  %-24s %s\n' "$id" "${translator:-Arabic only, no translation}"
    fi
  done <<< "$CATALOG"
  echo
  echo "  all                      import every edition above"
  return 0
}

if [ $# -ne 1 ]; then usage; exit 64; fi
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then usage; exit 0; fi

if [ ! -d "$CACHE_DIR/.git" ]; then
  echo "Fetching $DATASET_REPO at $DATASET_REF ..."
  mkdir -p "$(dirname "$CACHE_DIR")"
  git -c advice.detachedHead=false clone --quiet --depth 1 \
    --branch "$DATASET_REF" "$DATASET_REPO" "$CACHE_DIR"
else
  echo "Using cached dataset in $CACHE_DIR"
fi

import_one() {
  local id="$1" file="$2" translator="$3"
  local input="$CACHE_DIR/$file"

  if [ ! -f "$input" ]; then
    echo "Error: $input not found in the dataset." >&2
    return 66
  fi

  echo "Importing $id ..."
  # The dataset nests verses under each surah, so --group-path "" walks the
  # root array of 114 surahs and --verses-key reads the verses inside each.
  dart run tool/import_quran.dart \
    --input "$input" \
    --edition "$id" \
    --source-name "$SOURCE_NAME" \
    --source-url "$DATASET_URL" \
    --licence "$DATASET_LICENCE" \
    ${translator:+--translator "$translator"} \
    --group-path "" \
    --verses-key verses \
    --group-map number=id \
    --group-map nameArabic=name \
    --group-map nameEnglish=transliteration \
    --map ayah=id \
    --map arabic=text \
    --map translation=translation \
    --join-input "$CACHE_DIR/$TRANSLITERATION" \
    --join-field transliteration \
    --reference-template "{surahName} {surah}:{ayah}"
}

if [ "$1" != "all" ] && ! grep -q "^$1|" <<< "$CATALOG"; then
  echo "Error: unknown edition \"$1\"." >&2
  usage >&2
  exit 64
fi

# A here-string rather than a pipe, so this runs in the current shell and a
# failing import aborts the script instead of being swallowed by a subshell.
while IFS='|' read -r id file translator; do
  if [ -z "$id" ]; then
    continue
  fi
  if [ "$1" = "all" ] || [ "$1" = "$id" ]; then
    import_one "$id" "$file" "$translator"
  fi
done <<< "$CATALOG"

echo
echo "Done. Verify with:"
echo "  flutter test test/data/bundled_assets_test.dart"
echo "  flutter run"
