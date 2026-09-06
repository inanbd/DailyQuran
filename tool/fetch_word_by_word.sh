#!/usr/bin/env bash
#
# Downloads word-by-word data from the Quran.com API (v4) and builds the app's
# shared word index at assets/data/word_by_word.json.
#
#   ./tool/fetch_word_by_word.sh          # English (default)
#   ./tool/fetch_word_by_word.sh urdu
#
# The glosses come from the Quranic Universal Library by way of Quran.com, and
# are derived from the Quranic Arabic Corpus. They are a word-level aid to
# reading the Arabic, NOT a translation of the ayah — the app labels them that
# way and never substitutes one for the other.
#
# BEFORE YOU SHIP THIS: check Quran.com's terms and the licence of the
# underlying corpus, and satisfy yourself that you may redistribute the glosses
# inside a published app. See DATA_SOURCES.md.
#
# Only the raw pages are downloaded here; assembling them into the app's format
# is `tool/import_word_by_word.dart`, so the conversion is testable and does not
# depend on the network.

set -euo pipefail

LANGUAGE="${1:-english}"
API="https://api.quran.com/api/v4"
CACHE_DIR="${QURAN_WBW_CACHE:-.dart_tool/quran-wbw}"
PER_PAGE=50
SURAH_COUNT=114

usage() {
  echo "Usage: $0 [language]"
  echo
  echo "  language   word-translation language as named by the Quran.com API"
  echo "             (english, urdu, bangla, indonesian, …). Default: english."
  return 0
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then usage; exit 0; fi

mkdir -p "$CACHE_DIR"

echo "Fetching word-by-word ($LANGUAGE) from $API ..."
for surah in $(seq 1 "$SURAH_COUNT"); do
  page=1
  while :; do
    out="$CACHE_DIR/${surah}_${page}.json"
    if [ ! -s "$out" ]; then
      curl -sS --fail --max-time 60 --retry 3 --retry-delay 2 \
        "$API/verses/by_chapter/$surah?words=true&word_fields=text_uthmani&word_translation_language=$LANGUAGE&per_page=$PER_PAGE&page=$page" \
        -o "$out"
    fi

    # Stop when the API says there is no next page. Read with grep rather than
    # jq so the script needs nothing beyond curl.
    if grep -q '"next_page":null' "$out"; then break; fi
    page=$((page + 1))
    if [ "$page" -gt 20 ]; then
      echo "Error: surah $surah paginated past 20 pages; giving up." >&2
      exit 65
    fi
  done
  printf '\r  surah %3d/%d' "$surah" "$SURAH_COUNT"
done
echo

echo "Building the word index ..."
dart run tool/import_word_by_word.dart \
  --input-dir "$CACHE_DIR" \
  --language-name "$LANGUAGE" \
  --source-name "Quran.com API v4 (Quranic Universal Library); word-by-word glosses derived from the Quranic Arabic Corpus" \
  --source-url "https://api.quran.com/api/v4" \
  --licence "See Quran.com terms and the Quranic Arabic Corpus licence"

echo
echo "Done. Verify with:"
echo "  flutter test test/data/bundled_assets_test.dart"
echo "  flutter run"
