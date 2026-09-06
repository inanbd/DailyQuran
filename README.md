# Daily Quran

A quiet reading app: one ayah at a time, one gentle reminder, steady progress.

You choose a translation, choose when you want to be reminded, and read the
Qur'an through in order. Your place is saved and follows you from one
translation to another, nothing is marked read unless you read it, and the whole
reading experience works offline. No account, no feed, no streaks.

---

## Contents

- [Reading model](#reading-model)
- [Qur'an text and source integrity](#quran-text-and-source-integrity)
- [Recitation](#recitation)
- [Getting started](#getting-started)
- [Importing an edition](#importing-an-edition)
- [Project structure](#project-structure)
- [Architecture](#architecture)
- [Notifications](#notifications)
- [Testing](#testing)
- [Building for release](#building-for-release)
- [Accessibility](#accessibility)
- [Privacy](#privacy)
- [Licences](#licences)

---

## Reading model

The rule the whole app turns on:

> **Stay on what you read this period; otherwise move to the first ayah you
> have not read.**

That single rule produces the behaviour the product needs:

| Situation | What happens |
|---|---|
| First open | The first ayah |
| Read today, reopen tonight | The same ayah — no jumping ahead |
| Read yesterday, open after the reminder time | The next unread ayah |
| Missed a fortnight | The first ayah you never read, not the 14th |
| Skipped ahead to 2:255 and read it | Tomorrow returns to the ayah you skipped |
| Changed translation | Exactly where you were, in the new translation |
| Finished the Qur'an | A completion state; no wrapping around |

A reminder **firing** never changes progress. Progress changes only when the
reader actually reads:

- pressing *Mark as read*,
- opening an ayah from a reminder tap,
- or **reading one through**: once the end of the ayah has been on screen for
  5 seconds (`TodayScreen.dwell`), it marks itself. An ayah scrolled past on the
  way to *Next* is not marked, and a reader who marks one back as unread is
  never overruled — auto-marking happens at most once per ayah.

Moving between ayat is browsing, not reading: the arrows, a horizontal swipe on
the reading surface, and the surah index all change position without marking
anything.

A "period" is the interval between reminders, so a weekly reader advances weekly
and a daily reader advances daily. With reminders switched off it falls back to a
daily boundary at the configured time, so the reading still moves on each day.

The rule lives in
[`lib/domain/services/reading_scheduler.dart`](lib/domain/services/reading_scheduler.dart)
and is covered directly by
[`test/domain/reading_scheduler_test.dart`](test/domain/reading_scheduler_test.dart).

### Your place is the ayah's, not the translator's

Ayah 2:255 is the same ayah whichever translation renders it. So reading
progress and saved ayat are stored against a **scope** and a **verse key**
(`2:255`), never against an edition id:

- Every complete edition of the Qur'an declares `"progressScope": "quran"` in
  the catalog and therefore shares one place. Switching from Saheeh
  International to Hamidullah keeps your position, your read count and your
  favourites, and re-renders them in the new translation.
- The development fixture declares no scope, so it keeps its own. Placeholder
  reading can never show up as progress through the Qur'an.

This is the one deliberate departure from a shelf-of-separate-books model, and
it is what makes changing translation cost nothing.

## Qur'an text and source integrity

**Nothing in this project generates, paraphrases, completes or corrects Qur'an
text or any translation of it.** Text is copied verbatim from a dataset you
choose and can vouch for, and it always travels with an attribution record —
shown on the edition screen and gathered under **Settings → Qur'an sources**.

Two things ship with the app:

- **`dev_sample` ("Development Sample")** — placeholder prose written for this
  repository to exercise layout, typography and right-to-left rendering. Every
  field of it is developer text; it is labelled a development fixture in the
  catalog, tagged as such on every screen that shows it, and hidden from the
  library as soon as any verified edition is readable.
- **`saheeh_international`** — the Uthmani Arabic text with the Saheeh
  International English translation and an English transliteration, imported
  from [`quran-json`](https://github.com/risan/quran-json) under CC BY-SA 4.0.
  See [Licences](#licences).

Everything else in the catalog is bibliographic metadata only, and shows a
**Dataset not installed** state until you import it.

The bundled surah index (`assets/data/surahs.json`) is reference data — names,
lengths and Meccan/Medinan classification for all 114 surahs — and contains no
Qur'an text. It ships with the app so the surah list works before anything is
imported, and its ayah counts sum to 6,236, which the test suite asserts.

See [DATA_SOURCES.md](DATA_SOURCES.md) for the data contract and what to check
before importing an edition.

## Recitation

The app will read a **translation** aloud through the device's text-to-speech
voice, in the language the edition declares — a French translation is spoken by
a French voice, not an English one.

It will **not** do the same for the Arabic, and there is no setting to turn that
on. Recitation of the Qur'an is its own discipline, with rules of tajwid that a
text-to-speech engine neither knows nor follows; offering a button for it would
invite readers to treat the two as equivalent. The absence is asserted by
[`test/features/speech_test.dart`](test/features/speech_test.dart) so it cannot
be reintroduced by accident.

## Getting started

Requirements: Flutter **3.27+** (developed against 3.47.2 / Dart 3.13) and the
platform toolchains you intend to build for.

```bash
flutter pub get
flutter run
```

On first launch you get three onboarding steps — why, which translation, when —
and then the Today screen.

## Importing an edition

The quickest route is the open [`quran-json`](https://github.com/risan/quran-json)
dataset (CC BY-SA 4.0): the Uthmani text from The Noble Qur'an Encyclopedia with
translations and an English transliteration from Tanzil.net.

```bash
./tool/fetch_quran_json.sh hamidullah   # or: all
flutter run
```

Available editions: `arabic_uthmani`, `saheeh_international`, `maududi`,
`hamidullah`, `garcia`, `kuliev`, `muhiuddin_khan`.

For any other dataset, `tool/import_quran.dart` converts it into the app's asset
format and records its attribution. It copies text verbatim and skips entries
that have no text rather than filling gaps.

```bash
dart run tool/import_quran.dart \
  --input path/to/quran_en.json \
  --edition saheeh_international \
  --source-name "Name of the dataset" \
  --source-url https://example.org/dataset \
  --licence "The dataset's licence" \
  --group-path "" --verses-key verses \
  --group-map number=id \
  --map ayah=id --map arabic=text --map translation=translation \
  --reference-template "{surahName} {surah}:{ayah}"
```

The importer handles both shapes datasets come in: a flat array of ayat
(`--array-path`), or an array of surahs each nesting its own verses
(`--group-path` + `--verses-key`). `--join-input` merges a second file on
(surah, ayah), which is how transliterations are usually published. Run
`dart run tool/import_quran.dart --help` for the full list.

It writes `assets/data/editions/<slug>.json` and updates
`assets/data/catalog.json` with the real ayah count and source. Because the
pubspec declares the whole `assets/data/editions/` directory, the new edition
appears on the next build with **no code change** — that is the point of the
content layer.

To verify an import:

```bash
flutter test test/data/bundled_assets_test.dart test/features/real_dataset_smoke_test.dart
```

Those check, among other things, that a 6,236-ayah edition lines up with the
bundled surah index surah by surah, and that Ayat al-Kursi lands at reading
position 262 — an off-by-one anywhere in an import shows up there.

## Project structure

```
lib/
  app/          Providers, router, bootstrap, route table
  core/         Errors and formatting helpers
  data/
    content/    Asset-backed content source (the swappable seam)
    local/      SQLite database, DAOs, preferences store
    models/     JSON → entity parsing
    notifications/  flutter_local_notifications adapter, battery-optimisation
                    and system-settings channel
    repositories/   Repository implementations
  domain/
    entities/     Editions, ayat, surahs, progress, preferences
    repositories/ Abstract contracts
    services/     Reminder maths and the reading rule (pure Dart)
  features/
    onboarding/ library/ progress/ settings/ shell/ splash/
    today/      Reading surface, surah index, auto-marking, swipe
  shared/
    theme/      Colours, typography, spacing, ThemeData
    widgets/    Reusable components
assets/
  data/         Edition catalog, surah index, per-edition JSON
  fonts/        Inter and Noto Naskh Arabic (OFL)
tool/
  import_quran.dart, fetch_quran_json.sh
```

## Architecture

Four layers, each depending only on the one below:

**UI** (`features/`, `shared/`) → **State** (Riverpod controllers) →
**Repositories** (`domain/repositories` contracts, `data/repositories` impls) →
**Sources** (SQLite, shared preferences, content source, notification plugin).

Some deliberate choices:

- **The content source is one interface.**
  [`QuranContentSource`](lib/domain/repositories/quran_content_source.dart) is
  the only thing that knows where Qur'an text comes from. The bundled
  implementation reads JSON assets; a network or publisher-backed one can
  replace it by overriding a single provider. Nothing in the UI changes.
- **Content is copied into SQLite on first open.** Reading, paging and progress
  then run entirely against local storage, which is what makes the app work
  offline and keeps 6,236 ayat cheap to page through.
- **Progress is keyed by verse key within a scope**, which is what lets a change
  of translation carry the reader's place and their favourites with it.
- **Scheduling maths is pure Dart.**
  [`ReminderSchedule`](lib/domain/services/reminder_schedule.dart) and
  [`ReadingScheduler`](lib/domain/services/reading_scheduler.dart) have no
  Flutter or platform dependencies, so the tricky parts — weekday cadences,
  period boundaries, missed days — are tested directly.
- **Progress is one row per ayah actually read.** Nothing is ever inferred in
  bulk, which is what guarantees skipped ayat stay unread.
- **The clock is injectable** (`clockProvider`), so "the next morning" is a test
  assertion rather than a wait.
- **An edition declares its own language and direction**, so a French
  translation is spoken by a French voice and an Urdu one is laid out
  right-to-left, without the app guessing from the text.

## Notifications

- **Permission is never requested at launch.** The OS prompts are raised at the
  end of onboarding, after the reader has picked a time — or when they turn
  reminders on in settings. Both go through
  [`ReminderPermissionFlow`](lib/features/settings/reminder_permission_flow.dart).
- **Three things have to be allowed**, tracked separately by
  [`ReminderReadiness`](lib/domain/entities/reminder_readiness.dart), because
  "arrives two hours late" and "never arrives" are different problems with
  different fixes:
  - *Notifications* — without it nothing arrives. Asked for with the OS's own
    dialog. Once refused, Android stops showing that dialog, so the settings
    screen offers a way into system settings instead.
  - *Exact timing* (`SCHEDULE_EXACT_ALARM`) — without it Android may hold a
    reminder until the device next wakes, which under Doze can be hours.
  - *Unrestricted battery use* — without it the phone can put the app to sleep
    and drop its pending alarms. Raised through the `MainActivity` method
    channel, which `flutter_local_notifications` does not cover.
- **Declining never breaks anything.** Reminders still switch on; they are armed
  as inexact alarms instead, and the *Delivery* section of notification settings
  keeps the fix on offer. Granting one later re-arms the reminders, so the more
  accurate mode actually takes effect.
- **Times are wall-clock.** 8:00 AM is resolved against the device's *current*
  timezone every time reminders are armed, so travel and daylight-saving changes
  are handled without the reader doing anything.
- **Daily, weekly and selected-day cadences are armed as OS-level repeating
  notifications**, so they survive a device restart and an app update without
  the app running. Every-other-day has no repeating equivalent, so a rolling
  window of occurrences is armed and topped up on each launch.
- **Reminders are re-armed on every launch** (`bootstrapProvider`), which also
  covers timezone changes and frequency edits.
- **Changing any setting cancels everything and re-arms**, so a stale reminder
  can never survive a frequency change.
- **The notification never contains Qur'an text**, and never names the
  translation — only an invitation to open the app. Tapping it deep-links to the
  reader's current position.

Android needs core library desugaring for the notification plugin; it is already
configured in `android/app/build.gradle.kts`, along with ProGuard rules that keep
the plugin's models so reminders survive R8.

`flutter_local_notifications` stopped declaring its own broadcast receivers at
version 16, so `android/app/src/main/AndroidManifest.xml` declares them: without
`ScheduledNotificationReceiver` an alarm fires and nothing posts the
notification, and without `ScheduledNotificationBootReceiver` reminders do not
come back after a restart or an app update.

## Testing

```bash
flutter analyze     # lib, test and tool must be clean
flutter test
```

136 tests cover the reminder cadences and period boundaries, the reading rule
(including missed days and skipping ahead), the SQLite progress layer and its
shared scope, JSON parsing and error states, the repository install path, the
reading surface in each language mode, transliteration and right-to-left
translations, reading the translation aloud (and never the Arabic), auto-marking
and its guard rails, swipe navigation, the surah index, notification scheduling
and permission handling, and the full first-run journey end to end.

`test/features/main_journey_test.dart` runs the exact scenario the product is
built around: install → Saheeh International → Arabic + translation → daily at
8:00 AM → the first ayah → next morning's reminder → the second ayah →
`2 / 6,236`.

## Building for release

**Android**

```bash
flutter build appbundle --release   # Play Store
flutter build apk --release         # sideload / testing
```

Before publishing, replace the debug signing config in
`android/app/build.gradle.kts` with your own keystore.

**iOS**

```bash
flutter build ipa --release
```

Then open `ios/Runner.xcworkspace` in Xcode, set your team and bundle
identifier, and distribute. `ios/Runner/AppDelegate.swift` already sets the
`UNUserNotificationCenter` delegate, which is what lets a reminder show while the
app is in the foreground and lets taps reach Dart.

## Accessibility

- Reading text size is a preference that **multiplies** the platform's dynamic
  type rather than replacing it, so system accessibility settings keep working.
  Scaling is clamped to a range the reading layout can still honour.
- Arabic is laid out right-to-left with generous leading, in Noto Naskh Arabic,
  with `locale` set so the correct glyphs are selected. Qur'anic orthography
  stacks marks above and below the line, which is why the Arabic is set larger
  and more open than anything else in the app. A dedicated Uthmani face can be
  dropped into `assets/fonts/` and named in the pubspec if you have one you can
  license. Flutter does not currently expose a per-node screen-reader language,
  so the reader's system voice setting decides how Arabic is spoken.
- A translation that reads right-to-left declares itself in the catalog and is
  laid out and aligned accordingly.
- Progress bars announce a single sentence rather than three fragments; edition
  cards announce translation, translator, language, size and progress as one
  label.
- All controls meet a 48dp minimum touch target, and the palette meets WCAG AA
  in both themes.

## Privacy

No account, no analytics, no advertising SDK, no location or contacts access.
Reading progress, favourites and preferences stay in local storage on the device.
Every permission the app asks for serves reminders — notifications, exact alarms,
and an exemption from battery optimisation — and none is requested until the
reader has chosen a reminder time. Declining any of them costs punctuality,
nothing else.

## Licences

Application code in this repository is available for you to license as you see
fit. Bundled third-party assets carry their own terms:

- **Inter** — SIL Open Font License 1.1 (`assets/fonts/OFL-Inter.txt`)
- **Noto Naskh Arabic** — SIL Open Font License 1.1
  (`assets/fonts/OFL-NotoNaskhArabic.txt`)
- **`assets/data/editions/saheeh_international.json`** — adapted from
  [`quran-json`](https://github.com/risan/quran-json) and therefore distributed
  under **CC BY-SA 4.0**. Attribution travels with the file, in its own `source`
  block and in `assets/data/catalog.json`, and the app shows it under
  **Settings → Qur'an sources**. If you adapt that file further, your version
  carries the same licence. This applies to the data file, not to the
  application code alongside it.

Any other edition you import carries its own licence and attribution; record
them with the importer's `--licence` and `--source-name` flags so they are shown
in the app.
