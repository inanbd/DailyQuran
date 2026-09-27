# Daily Quran

A quiet reading app: one ayah at a time, gentle reminders, steady progress.

You choose a translation — seven ship with the app, in six languages — choose
when you want to be reminded and how much you want to read, and work through the
Qur'an in order. Your place is saved and follows you from one translation to
another, nothing is marked read unless you read it, and the whole reading
experience works offline. No account, no feed. There is a streak, but it only
ever counts up and praises: a missed day starts it again without a word.

---

## Contents

- [Reading model](#reading-model)
- [The Qur'an Planner](#the-quran-planner)
- [Reading time, streaks and milestones](#reading-time-streaks-and-milestones)
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
- [Releasing](#releasing)
- [Accessibility](#accessibility)
- [Privacy](#privacy)
- [Licences](#licences)

---

## Reading model

The rule the whole app turns on:

> **Stay on what you read this period once its portion is finished; otherwise
> move to the first ayah you have not read.**

On the Daily Ayah the portion is a single ayah, so it finishes the moment
anything is read and the rule reads as it always did — read one ayah, and the
app holds you there for the rest of the day. On a plan asking for eighteen a
day, the same sentence carries you through all eighteen and then stops. (The two
are separate readings, each applying the rule to its own progress — see
[The Qur'an Planner](#the-quran-planner).)

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

Finish the whole Qur'an by a day you choose. Under **Progress → Qur'an
Planner** (also reachable from Settings):

| Plan | What it works out to |
|---|---|
| **Finish in 1 month** | About 202 ayat a day · around 1 h 5 min |
| **Finish in 1 year** | About 18 ayat a day · around 6 min |
| **Pick a finish date** | Whatever your date works out to — picked on a calendar, up to five years out |

Each choice also says roughly how long a day of it takes, timed for what is on
the reader's screen: about 12 seconds an ayah for the Arabic and 8 for each
translation, so 20 for the Arabic with one translation. Those are the Qur'an's
own averages, measured over the bundled editions — 12.4 Arabic words an ayah
and 20 to 33 words of translation — at the pace of a measured recitation
(about 65 words a minute) and ordinary reading (about 200). The planner says
plainly that it is a rough guide. See
[`ReadingPace`](lib/domain/services/reading_pace.dart).

With no plan, the app is what it always was: the Daily Ayah, one ayah a
reading period.

Both endpoints count as days you can read on, so a month is 31 readings rather
than 30. The planner screen and the scheduler share that arithmetic
(`ReadingPlan.nominalPerDay`), and a test pins them together — a screen
advertising 208 a day while the engine asked for 202 would be lying about the
only number on it.

### Two readings, kept apart

A plan is read on its own track, separate from the Daily Ayah. Each has its
own place in the Qur'an and its own record of what has been read, so reading
one never counts towards — or against — the other. The **Read** tab switches
between them with **My Plan** / **Daily Ayah**, which takes the place of the
page title; the Progress tab shows both. A second translation shows beneath
either reading.

Under the hood a track is just a progress scope: the Daily Ayah keeps the
edition's own scope (`quran`), where every reader's existing progress already
lives, and the plan uses a sibling (`quran#plan`) — see
[`ReadingTrack`](lib/domain/entities/reading_track.dart). A plan saved by an
earlier version, when plans shared the Daily Ayah's progress, is carried over
once at startup (`carryOverLegacyPlan`), so an update never sets it back.

### Today's goal, first

A plan has its own daily reminder (on by default, 7:00 AM, changeable in the
planner, and up to five times a day). Each reminder carries that day's goal —
"202 ayat to read today" — and tapping it opens **Today's goal**: how much to
read, how much is done, where the reading picks up, and how the plan is going,
with one **Continue reading** button. Nothing is marked read by opening it. A
later reminder on the same day says what is left of the goal — "150 ayat left
of today's goal".

Because the goal changes from day to day, the plan's reminders are armed one
at a time — a rolling window of 28, re-armed whenever the app is used —
rather than as one repeating alarm, each with the goal as it will stand that
day. A day whose goal is already met gets no more reminders. See
[`PlanReminderComposer`](lib/domain/services/plan_reminder_composer.dart).

The Daily Ayah's reminder is unchanged: tapping it opens the Daily Ayah and
marks it read.

### A plan's day is a calendar day

A plan's goal is for the day on the calendar, midnight to midnight
(`PlanScheduler.calendarDays`). The Daily Ayah still rolls on with its own
reminder's cadence.

### Missing days makes the next goal bigger

Nothing is ever marked read because time passed, so missing a fortnight leaves
exactly those ayat unread — with fewer days left to read them in. The goal is
simply

    what is left ÷ days left

recomputed every day, so it grows on its own and the date holds. Reading extra
does the opposite: every day after gets lighter. There is no backlog written
down anywhere and nothing to "clear".

Two guard rails stop that arithmetic turning cruel:

- **Past the date**, a plan stops demanding everything at once. It falls back to
  its original steady rate and reports an honest new finish date instead.
- **The goal is computed from the state at the start of the day**, so it
  cannot recede as you read through it — a goal of four stays a goal of four
  until it is done.

And because a deadline still needs a way out, the planner offers three under
**Start over**, none of which touch the Daily Ayah:

- **Plan again from today** keeps everything the plan has read and measures the
  rest from today. A chosen-date plan is asked for its new date.
- **Start from the first ayah** (confirmed first) clears the plan's reading and
  starts it again from today.
- **Stop my plan** (confirmed first) turns the planner off and clears the
  plan's reading.

The arithmetic is pure Dart in
[`lib/domain/services/plan_scheduler.dart`](lib/domain/services/plan_scheduler.dart)
and covered directly by
[`test/domain/plan_scheduler_test.dart`](test/domain/plan_scheduler_test.dart).

## Reading time, streaks and milestones

The app notices when a reader keeps at it, and says so. It only ever praises:
nothing remarks on a missed day, a shorter reading or a streak that ended.

### Reading time

Under **Settings → Reading → Daily reading time** a reader can set a goal of
5 to 60 minutes a day. Time is measured, never assumed:

- It counts only while an ayah is on the reading screen, the app is in the
  foreground and the Read tab is the one showing.
- It counts for at most two minutes past the reader's last touch, scroll or
  page turn. A phone left open on the page overnight is not eight hours of
  reading; the clock stops where it was fair to assume they stopped, and starts
  again at the next touch.
- A reading that runs past midnight counts towards both days, each for its own
  part.

The measuring is pure Dart in
[`ReadingSession`](lib/domain/services/reading_session.dart); the Today screen
feeds it through [`ReadingTimer`](lib/features/activity/reading_timer.dart).
Time is kept per calendar day in the `reading_day` table.

With a goal set, the Today screen shows a thin bar for it ("Reading time · 4 of
10 min today"). The **Progress** tab shows the streak, today's and the last seven
days' reading time, and the week against the week before: "Up 15 min on the
week before. MashaAllah — keep it up." A shorter week gets the plain figure and
nothing else.

### The streak

A day counts towards the streak when the reader **meets the goal they set**:

| Goals set | The day counts when… |
|---|---|
| A reading time | they read for that long |
| A plan | they meet the plan's goal for the day |
| Both | they do either |
| Neither | they read the Daily Ayah |

A bigger goal, once chosen, replaces the Daily Ayah: reading one ayah on a day
that asks for two hundred is not meeting the day. A day's goal is met once and
kept — marking an ayah back as unread, or changing the goal later that day, does
not take the day back. Streaks begin with this version; nothing is
reconstructed from before it. See
[`DailyGoal` and `ReadingStreak`](lib/domain/services/daily_goal.dart).

### What is congratulated

| When | Says |
|---|---|
| Every 3 days in a row of meeting the goal | "3 days in a row" |
| Every tenth of the Qur'an, on either reading | "30% of the Qur'an" |
| The day's reading time reached | "Today's reading time is done" |
| More reading today than yesterday (when yesterday had at least a minute) | "Longer than yesterday" |

Each is said once, at the moment it is earned: every check compares the reading
just before something happened with the reading just after, and speaks only when
a line was crossed. A milestone is also recorded (the `milestone` table), so a
tenth passed, un-read and read again is not a new one; starting a reading over
clears its milestones along with its progress. Finishing the Qur'an keeps its
own completion screen rather than a hundredth congratulation on top of it.
Several earned at once share one sheet. See
[`Encouragement`](lib/domain/services/encouragement.dart) and
[`ReadingActivity`](lib/features/activity/reading_activity.dart).

**Settings → Reading → Celebrate milestones** turns the congratulations off.
Everything is still recorded, so the Progress tab is unchanged and turning them
back on loses nothing.

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
    services/     Reminder maths, the reading rule, plan goals, reading
                  time, streaks, congratulations and reminder text
                  (all pure Dart)
  features/
    onboarding/ library/ progress/ settings/ shell/ splash/
    activity/   Reading time on the Today screen, the streak and week on
                Progress, the congratulation sheet
    planner/    The Qur'an Planner, today's goal screen, the plan's status
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
  icon/         The app icon, drawn in code, and what renders every size
  new_keystore.ps1
fastlane/metadata/android/
                Google Play listing: text, graphics, release notes
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
    and drop its pending alarms. The `MainActivity` method channel, which
    `flutter_local_notifications` does not cover, opens the system's battery
    optimisation list, where the reader turns it off for Daily Quran. The
    one-tap dialog is not used: its permission,
    `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, is one Google Play allows only for
    apps whose core function needs it.
- **Declining never breaks anything.** Reminders still switch on; they are armed
  as inexact alarms instead, and the *Delivery* section of notification settings
  keeps the fix on offer. Granting one later re-arms the reminders, so the more
  accurate mode actually takes effect.
- **Times are wall-clock.** 8:00 AM is resolved against the device's *current*
  timezone every time reminders are armed, so travel and daylight-saving changes
  are handled without the reader doing anything.
- **Up to five reminders a day.** The first of the day brings the next Daily
  Ayah — it is where the reading period starts, so three reminders still mean
  one ayah a day. The later ones are nudges back to that same ayah, and once it
  has been read they fall quiet until the next period
  (`NotificationScheduler.reschedule(quietUntil:)`).
- **Daily, weekly and selected-day cadences are armed as OS-level repeating
  notifications**, one per reminder time, so they survive a device restart and
  an app update without the app running. Quietening the rest of a day is done
  by arming each repeating reminder to *start* at its first occurrence after
  the quiet period. Every-other-day has no repeating equivalent, so a rolling
  window of occurrences is armed and topped up on each launch.
- **The 64-notification limit on iOS holds.** Five times on each of seven
  selected days is 35 repeating reminders; a plan's rolling window is kept to
  28 so the two together stay under it.
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

Only readers who changed one of these settings pay for any of it: on the default,
revealing nothing, the message is a constant and no lookup happens at all. (A
plan's own reminders are separate and always carry just the day's goal — see
[The Qur'an Planner](#the-quran-planner).)

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

Release builds sign with the key named in `android/key.properties`, and fall
back to the debug key when that file is absent. `tool/new_keystore.ps1`
creates the keystore and the properties file; neither is ever committed.

**The icon** — an open mushaf beneath an eight-point star, in the app's green
and gold — is drawn in code in
[`tool/icon/app_icon.dart`](tool/icon/app_icon.dart). After changing it,
render every size again:

```bash
flutter test tool/icon/generate_icons_test.dart
```

That writes Android's adaptive icon layers (with a monochrome one for themed
icons) and its pre-Android 8 icon, every iOS size (without an alpha channel,
which App Store Connect refuses), and Google Play's 512px icon and feature
graphic.

**iOS**

```bash
flutter build ipa --release
```

Then open `ios/Runner.xcworkspace` in Xcode, set your team and bundle
identifier, and distribute. `ios/Runner/AppDelegate.swift` already sets the
`UNUserNotificationCenter` delegate, which is what lets a reminder show while the
app is in the foreground and lets taps reach Dart.

## Releasing

Releases are built on GitHub Actions and published as GitHub Releases, with
that version's section of [`CHANGELOG.md`](CHANGELOG.md) as the notes
([`.github/workflows/release.yml`](.github/workflows/release.yml)). To publish
one:

1. Bump `version:` in `pubspec.yaml` (e.g. `1.2.0+3` → `1.2.1+4`).
2. Add a `## 1.2.1` section to `CHANGELOG.md`.
3. Commit and push.

A push that changes the version releases it as `v1.2.1` — once; pushing the
same version again does nothing. The workflow analyzes, runs the tests, builds
`DailyQuran-v1.2.1.apk`, and attaches it (with its SHA-256) to the release.
Pushing a `v*` tag, or running the workflow from the Actions tab, also works.

### Signing releases with your own key

Without signing secrets, a release is signed with a throwaway debug key — fine
for trying the app, but each such build has a different signature, so Android
will not install one over another (or over a build you signed yourself)
without uninstalling first. To sign with the app's own key, add these under
**Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | The keystore file, base64-encoded: `[Convert]::ToBase64String([IO.File]::ReadAllBytes('android\keystore.jks'))` in PowerShell, or `base64 -w0 android/keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | The keystore password |
| `ANDROID_KEY_ALIAS` | The key alias (`dailyquran` if made with `tool/new_keystore.ps1`) |
| `ANDROID_KEY_PASSWORD` | The key password, if different from the keystore's |

Every release after that installs over the last.

### Google Play

Play takes an app bundle signed with the upload key, which lives only on the
machine that holds `android/key.properties`:

```bash
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab
```

Upload it in Play Console under **Test and release**. What the listing needs
is kept in the repository, in the layout `fastlane supply` reads:

| File | Play Console field |
|---|---|
| `fastlane/metadata/android/en-US/title.txt` | App name (30 characters) |
| `…/short_description.txt` | Short description (80) |
| `…/full_description.txt` | Full description (4,000) |
| `…/changelogs/<versionCode>.txt` | Release notes (500) |
| `…/images/icon.png` | App icon, 512 × 512 |
| `…/images/featureGraphic.png` | Feature graphic, 1024 × 500 |
| `…/images/phoneScreenshots/` | Phone screenshots, 1080 × 2160 |

Add a `changelogs/<versionCode>.txt` with each version. Play refuses a
screenshot more than twice as tall as it is wide, and one with an alpha
channel, so a 1080 × 2400 phone's own screenshots need the screen set to
`adb shell wm size 1080x2160` first and saving as 24-bit. The privacy policy
Play asks for is [`PRIVACY.md`](PRIVACY.md).

The APK on a GitHub Release is signed differently from the one Play delivers,
so a phone cannot move from one to the other without uninstalling.

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
Reading progress, favourites, plans, reading time and preferences stay in local
storage on the device. Every permission the app asks for serves reminders — notifications,
exact alarms, and an exemption from battery optimisation — and none is requested
until the reader has chosen a reminder time. Declining any of them costs
punctuality, nothing else.

The one place the app can put anything where someone other than the reader might
see it is the lock screen, and it does so only on request: reminders reveal
nothing by default, and the setting that changes that says plainly what it will
show and where. See [What the reminder says](#what-the-reminder-says).

The published privacy policy is [`PRIVACY.md`](PRIVACY.md).

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
