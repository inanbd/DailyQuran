# Daily Quran

A quiet reading app: one ayah at a time, one gentle reminder, steady progress.

You choose a translation — seven ship with the app, in six languages — choose
when you want to be reminded and how much you want to read, and work through the
Qur'an in order. Your place is saved and follows you from one translation to
another, nothing is marked read unless you read it, and the whole reading
experience works offline. No account, no feed, no streaks.

---

## Contents

- [Reading model](#reading-model)
- [Reading plans](#reading-plans)
- [Qur'an text and source integrity](#quran-text-and-source-integrity)
- [Choosing a translation](#choosing-a-translation)
- [Word-by-word tarjama](#word-by-word-tarjama)
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

> **Stay on what you read this period once its portion is finished; otherwise
> move to the first ayah you have not read.**

On the default plan the portion is a single ayah, so it finishes the moment
anything is read and the rule reads as it always did — read one ayah, and the
app holds you there for the rest of the day. On a plan asking for eighteen, the
same sentence carries you through all eighteen and then stops.

That single rule produces the behaviour the product needs:

| Situation | What happens |
|---|---|
| First open | The first ayah |
| Read today's portion, reopen tonight | The last ayah of it — no jumping ahead |
| Read part of today's portion | The next ayah of it |
| Read yesterday, open after the reminder time | The next unread ayah |
| Missed a fortnight | The first ayah you never read, not the 14th |
| Skipped ahead to 2:255 and read it | Tomorrow returns to the ayah you skipped |
| Changed translation | Exactly where you were, in the new translation |
| Turned word-by-word on | The same ayah, its Arabic shown word by word |
| Finished the Qur'an | A completion state; no wrapping around |

A reminder **firing** never changes progress. Progress changes only when the
reader actually reads:

- pressing *Mark as read*,
- opening an ayah from a reminder tap,
- or **reading one through**: once the end of the ayah has been on screen for
  5 seconds (`TodayScreen.dwell`), it marks itself. An ayah scrolled past on the
  way to *Next* is not marked, and a reader who marks one back as unread is
  never overruled — auto-marking happens at most once per ayah.

Auto-marking marks but never turns the page, which is what keeps it safe on a
large portion: a dwell timer that also advanced would walk itself through the
whole day's reading, five seconds at a time, while the reader sat still.
Pressing *Mark as read* does advance, because that is a deliberate act.

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

## The Qur'an Planner

How much a reading period asks for, under **Settings → Qur'an Planner**:

| Pace | What it works out to |
|---|---|
| **One ayah a day** | One ayah a period, no end date. The default. |
| **In a month** | About 202 ayat a day |
| **In a year** | About 18 ayat a day |
| **By a chosen date** | Whatever your date works out to — picked on a calendar, up to five years out |

Both endpoints count as days you can read on, so a month is 31 readings rather
than 30. The planner screen and the scheduler share that arithmetic
(`ReadingPlan.nominalPerDay`), and a test pins them together — a screen
advertising 208 a day while the engine asked for 202 would be lying about the
only number on it.

A plan is either a *rate* or a *date*, and everything else follows from which.
"One ayah a day" sets a rate and lets the finish date fall where it may; the
others commit to a date — a month out, a year out, or wherever you put it —
and let the rate follow from it.

The planner's hero card keeps the whole journey visible: a ring of how much of
the Qur'an is read, today's portion, the days remaining, and the day it all
finishes on, with an honest sentence about whether you are on course, ahead,
or behind.

### Portions are per reading period, not per calendar day

A plan divides by the number of times you actually read, not by the number of
days on the calendar. A weekly reader working towards the same date gets a
week's worth at a time. That is what `ReminderSchedule.periodsBetween` counts.

### Missing days makes the next portion bigger

Nothing is ever marked read because time passed, so missing a fortnight leaves
exactly those ayat unread — with fewer periods left to read them in. The portion
is simply

    what is left ÷ periods left

recomputed every period, so it grows on its own and the date holds. There is no
backlog written down anywhere, nothing to "clear", and no streak to break.

Two guard rails stop that arithmetic turning cruel:

- **Past the date**, a plan stops demanding everything at once. It falls back to
  its original steady rate and reports an honest new finish date instead.
- **The target is computed from the state at the start of the period**, so it
  cannot recede as you read through it — a portion of four stays a portion of
  four until it is done.

And because a deadline still needs a way out, the planner offers two under
**Begin anew**:

- **Replan from today** re-baselines a plan without touching anything you have
  read. Someone who put the app down for two months picks it up again at a sane
  portion rather than an impossible one. A chosen-date plan is asked for its
  new date, because re-measuring towards the old one is rarely what a fresh
  start means.
- **Restart from the beginning** (confirmed first — it cannot be undone) marks
  every ayah unread and starts the reading and the plan again from the first
  ayah. Favourites are kept. Restarting a finished reading from the Today
  screen re-baselines the plan the same way; a chosen date that has already
  gone is replaced by a new window of the same length.

The arithmetic is pure Dart in
[`lib/domain/services/plan_scheduler.dart`](lib/domain/services/plan_scheduler.dart)
and covered directly by
[`test/domain/plan_scheduler_test.dart`](test/domain/plan_scheduler_test.dart).

## Qur'an text and source integrity

**Nothing in this project generates, paraphrases, completes or corrects Qur'an
text or any translation of it.** Text is copied verbatim from a dataset you
choose and can vouch for, and it always travels with an attribution record —
shown on the edition screen and gathered under **Settings → Qur'an sources**.

What ships with the app:

- **Seven editions**, all imported from
  [`quran-json`](https://github.com/risan/quran-json) under CC BY-SA 4.0: the
  Uthmani Arabic text on its own, and with the Saheeh International (English),
  Maududi (Urdu), Hamidullah (French), García (Spanish), Kuliev (Russian) and
  Muhiuddin Khan (Bengali) translations. Each carries an English
  transliteration. See [Licences](#licences).
- **A word-by-word index** — every ayah's words with the gloss the source gives
  each one. See [Word-by-word tarjama](#word-by-word-tarjama).
- **`dev_sample` ("Development Sample")** — placeholder prose written for this
  repository to exercise layout, typography and right-to-left rendering. Every
  field of it is developer text; it is labelled a development fixture in the
  catalog, tagged as such on every screen that shows it, and hidden from the
  library as soon as any verified edition is readable — which, now that real
  editions ship, is always.

A catalog entry whose dataset has not been imported shows a **Dataset not
installed** state rather than failing.

The bundled surah index (`assets/data/surahs.json`) is reference data — names,
lengths and Meccan/Medinan classification for all 114 surahs — and contains no
Qur'an text. It ships with the app so the surah list works before anything is
imported, and its ayah counts sum to 6,236, which the test suite asserts.

See [DATA_SOURCES.md](DATA_SOURCES.md) for the data contract and what to check
before importing an edition.

## Choosing a translation

The translation being read is named at the top of the reading screen, and
tapping it opens the list. Choosing another switches immediately and leaves the
reader on the same ayah: because progress and favourites are stored against the
ayah rather than the translator, nothing is lost and nothing has to be
re-synced. The library tab is still there for reading *about* an edition —
its translator, its source, its licence — before committing to it.

Only editions that can actually be opened are listed. The development fixture
is excluded, so placeholder text can never be one tap from the Qur'an.

## Word-by-word tarjama

Each Arabic word shown with what it means on its own, in place of the running
Arabic, laid out right-to-left so the reading order is the Arabic's.

It is a **reading aid, not a second translation**. A gloss says what one word
means in isolation; the ayah's translation says what the ayah means. The app
keeps them visually distinct and shows the ayah's own translation underneath
either way, and the bundled index says so in its own `notice` field — which the
test suite asserts.

Turn it on under **Settings → Reading → Show word by word**. It is off by
default, and the control does nothing on an edition with no glosses installed
rather than blanking the Arabic out.

The glosses live in one shared file, `assets/data/word_by_word.json`, and are
attached to every edition as it installs — they do not change with the
translation being read, so duplicating them into each edition would cost about
70 MB for nothing. Bring them in, or replace them with another language, with:

```bash
./tool/fetch_word_by_word.sh english   # or urdu, bangla, indonesian, …
```

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

All seven are already imported. To re-import them, or to pick up a change in
the dataset:

```bash
./tool/fetch_quran_json.sh all          # or one id
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
    entities/     Editions, ayat, surahs, progress, plans, preferences
    repositories/ Abstract contracts
    services/     Reminder maths, the reading rule, plan portions and
                  reminder text (all pure Dart)
  features/
    onboarding/ library/ progress/ settings/ shell/ splash/
    today/      Reading surface, surah index, translation chooser,
                auto-marking, swipe
  shared/
    theme/      Colours, typography, spacing, ThemeData
    widgets/    Reusable components
assets/
  data/         Edition catalog, surah index, word index, per-edition JSON
  fonts/        Inter and Noto Naskh Arabic (OFL)
tool/
  import_quran.dart, fetch_quran_json.sh
  import_word_by_word.dart, fetch_word_by_word.sh
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
- **What does not vary by translation lives once.** The surah index and the
  word-by-word glosses are the same for every edition, so they are shared files
  joined on at install time rather than copied into each one.
- **Words are stored as a column on the ayah, not a table of their own.** They
  are a value of the ayah — always read with it, never queried independently —
  and a second table would mean 77,000 more rows and a join for nothing.
- **Scheduling maths is pure Dart.**
  [`ReminderSchedule`](lib/domain/services/reminder_schedule.dart),
  [`ReadingScheduler`](lib/domain/services/reading_scheduler.dart) and
  [`PlanScheduler`](lib/domain/services/plan_scheduler.dart) have no Flutter or
  platform dependencies, so the tricky parts — weekday cadences, period
  boundaries, missed days, catch-up portions — are tested directly.
- **A plan's portion is derived, never stored.** Missed reading is not written
  down as a backlog to be reconciled; it is what is left divided by the periods
  left, recomputed each time. There is no second source of truth about progress
  to drift from the read table.
- **How much of a portion is done is counted, not tallied.** One `COUNT(*)` over
  rows read since the period began, so it stays correct however the reader moved
  about — ahead, back, or into another translation.
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
- **A notification never names the translation**, and tapping it deep-links to
  the reader's current position — never to an ayah the notification chose.

### What the reminder says

A notification is read on a lock screen by whoever happens to be looking at it.
That makes "how much should it reveal" a decision only the reader can make, so
the app asks, under **Settings → Notifications → What the reminder says**:

| Setting | Example |
|---|---|
| **Just an invitation** (default) | "Your next ayah is ready." |
| **Which ayah is next** | "Al-Baqarah 2:255 · 18 ayat" — a citation, no Qur'an text |
| **The translation** | "Allah — there is no deity except Him…" |
| **The Arabic** | The ayah's Arabic |

The default reveals nothing, and each step up reveals exactly one more thing.
Composition lives in
[`ReminderMessageComposer`](lib/domain/services/reminder_message_composer.dart),
in the domain layer, so the platform adapter is handed two strings and cannot
widen what it was given.

Two consequences worth knowing:

- **A setting that cannot be honoured steps down rather than failing.** An
  edition with no translation installed, or a reminder armed before any edition
  was chosen, falls back down the ladder — so a reader can be shown less than
  they asked for, but never a blank notification.
- **The text is a snapshot, not a subscription.** An OS-level repeating alarm
  carries fixed text, so a reminder that names an ayah names the one that was
  next when it was armed. The app therefore re-arms when it is backgrounded and
  when an edition's text first lands, not only at launch. Reading somewhere else
  on another device would still leave it a little behind, and the settings
  screen says so.

Only readers who changed one of these settings pay for any of it: on the default
plan revealing nothing, the message is a constant and no lookup happens at all.

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

202 tests cover the reminder cadences and period boundaries, the reading rule
(including missed days, skipping ahead and unfinished portions), reading-plan
arithmetic (catch-up, reading ahead, a target that cannot recede, and what
happens once the date has passed), what a reminder is allowed to say and its
fallbacks, the SQLite progress layer and its shared scope, the v1 → v2
migration, JSON parsing and error states, the repository install path, the
reading surface in each language mode, transliteration and right-to-left
translations, word-by-word glosses and the guarantee that they replace the
running Arabic rather than repeat it, switching translation without losing your
place, reading the translation aloud (and never the Arabic), auto-marking and
its guard rails, swipe navigation, the surah index, notification scheduling and
permission handling, and the full first-run journey end to end.

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
- In the word-by-word view each word is announced as one label — the Arabic and
  its gloss together — rather than as two disconnected fragments.
- Progress bars announce a single sentence rather than three fragments; edition
  cards announce translation, translator, language, size and progress as one
  label.
- All controls meet a 48dp minimum touch target, and the palette meets WCAG AA
  in both themes.

## Privacy

No account, no analytics, no advertising SDK, no location or contacts access.
Reading progress, favourites, plans and preferences stay in local storage on the
device. Every permission the app asks for serves reminders — notifications,
exact alarms, and an exemption from battery optimisation — and none is requested
until the reader has chosen a reminder time. Declining any of them costs
punctuality, nothing else.

The one place the app can put anything where someone other than the reader might
see it is the lock screen, and it does so only on request: reminders reveal
nothing by default, and the setting that changes that says plainly what it will
show and where. See [What the reminder says](#what-the-reminder-says).

## Licences

Application code in this repository is available for you to license as you see
fit. Bundled third-party assets carry their own terms:

- **Inter** — SIL Open Font License 1.1 (`assets/fonts/OFL-Inter.txt`)
- **Noto Naskh Arabic** — SIL Open Font License 1.1
  (`assets/fonts/OFL-NotoNaskhArabic.txt`)
- **Everything under `assets/data/editions/`** except the development fixture —
  adapted from [`quran-json`](https://github.com/risan/quran-json) and therefore
  distributed under **CC BY-SA 4.0**. Attribution travels with each file, in its
  own `source` block and in `assets/data/catalog.json`, and the app shows it
  under **Settings → Qur'an sources**. If you adapt those files further, your
  versions carry the same licence. This applies to the data files, not to the
  application code alongside them.
- **`assets/data/word_by_word.json`** — built from the
  [Quran.com API](https://api.quran.com/api/v4) (Quranic Universal Library),
  whose word-by-word glosses derive from the Quranic Arabic Corpus. **Check
  Quran.com's terms and the corpus's licence before publishing a build that
  contains it**; unlike the editions above, this one does not come with an
  explicit redistribution licence, and the choice to ship it is yours. See
  [DATA_SOURCES.md](DATA_SOURCES.md).

Any other edition you import carries its own licence and attribution; record
them with the importer's `--licence` and `--source-name` flags so they are shown
in the app.
