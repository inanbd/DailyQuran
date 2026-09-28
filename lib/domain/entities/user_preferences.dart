import 'package:meta/meta.dart';

import 'enums.dart';
import 'reading_plan.dart';
import 'reading_track.dart';

/// Reading and appearance preferences. Small enough to live in key-value
/// storage; nothing here is personal data.
@immutable
class UserPreferences {
  const UserPreferences({
    required this.languageMode,
    required this.showTransliteration,
    required this.showWordByWord,
    required this.themeMode,
    required this.textSize,
    required this.readingOrder,
    required this.onboardingComplete,
    this.plan = ReadingPlan.defaults,
    this.readingTrack,
    this.currentEditionId,
    this.secondaryEditionId,
    this.dailyReadingMinutes = 0,
    this.celebrations = true,
    this.readingLayout = ReadingLayout.swipe,
  });

  /// The daily reading times a reader can choose from, in minutes.
  static const List<int> readingMinuteChoices = <int>[5, 10, 15, 20, 30, 45, 60];

  static const UserPreferences defaults = UserPreferences(
    languageMode: LanguageMode.both,
    showTransliteration: false,
    showWordByWord: false,
    themeMode: AppThemeMode.system,
    textSize: TextSizePreference.standard,
    readingOrder: ReadingOrder.sequential,
    onboardingComplete: false,
  );

  final LanguageMode languageMode;

  /// Whether to show the Latin-script transliteration beneath the Arabic.
  ///
  /// Off by default and only ever shown where the installed edition actually
  /// carries one — the app never transliterates anything itself.
  final bool showTransliteration;

  /// Whether to show each Arabic word with the gloss the source gives it.
  ///
  /// A word-level reading aid, not a second translation: it says what each
  /// word means on its own. Off by default, and only ever shown where a word
  /// index has actually been installed.
  final bool showWordByWord;

  final AppThemeMode themeMode;
  final TextSizePreference textSize;
  final ReadingOrder readingOrder;
  final bool onboardingComplete;

  /// How much of the Qur'an a reading period asks for.
  ///
  /// Defaults to one ayah a period, so a reader who never opens the plan
  /// screen — and every reader upgrading from a version without plans — sees
  /// no change at all.
  final ReadingPlan plan;

  /// The reading the Today screen last showed, or null when the reader has
  /// never switched between them.
  final ReadingTrack? readingTrack;

  /// The reading the Today screen shows.
  ///
  /// Without a plan there is only the Daily Ayah. With one, it is whichever
  /// the reader last chose — and the plan until they choose, because a reader
  /// who has just set a goal expects to be taken to it.
  ReadingTrack get activeTrack {
    if (!plan.isPaced) return ReadingTrack.daily;
    return readingTrack ?? ReadingTrack.plan;
  }

  /// The edition the Today screen reads from. Null before onboarding finishes.
  final String? currentEditionId;

  /// A second translation shown beneath the first, or null for just the one.
  ///
  /// Two is the cap, and it is a cap on *translations*, not on panes: the
  /// Arabic is not one of the two. Beyond two the ayah stops being the thing
  /// on the screen and the page becomes a comparison table, which is a
  /// different app from this one.
  ///
  /// Only ever set to an edition sharing [currentEditionId]'s progress scope,
  /// so both columns are the same ayah and one mark-as-read still means one
  /// ayah read.
  final String? secondaryEditionId;

  /// The translations on screen, in the order they are shown. One or two.
  List<String> get editionIds => <String>[
        ?currentEditionId,
        ?secondaryEditionId,
      ];

  /// How long the reader means to spend reading each day, in minutes, or 0
  /// for no reading-time goal.
  ///
  /// Measured, never assumed: only time with an ayah on screen and the reader
  /// evidently reading it counts (see `ReadingSession`).
  final int dailyReadingMinutes;

  /// Whether reaching a streak or a milestone is marked with a word of
  /// congratulation. On by default; the record is kept either way, so turning
  /// it off quiets the app without losing anything.
  final bool celebrations;

  /// Whether the Read tab turns one ayah at a time or scrolls through them.
  /// Swiping by default, which is how every reader before this setting read.
  final ReadingLayout readingLayout;

  UserPreferences copyWith({
    LanguageMode? languageMode,
    bool? showTransliteration,
    bool? showWordByWord,
    AppThemeMode? themeMode,
    TextSizePreference? textSize,
    ReadingOrder? readingOrder,
    bool? onboardingComplete,
    ReadingPlan? plan,
    ReadingTrack? readingTrack,
    String? currentEditionId,
    String? secondaryEditionId,
    int? dailyReadingMinutes,
    bool? celebrations,
    ReadingLayout? readingLayout,
    /// Drops the second translation. Needed because a null
    /// [secondaryEditionId] above means "leave it alone", which would make
    /// turning the second translation back off impossible to express.
    bool clearSecondaryEdition = false,
  }) {
    return UserPreferences(
      languageMode: languageMode ?? this.languageMode,
      showTransliteration: showTransliteration ?? this.showTransliteration,
      showWordByWord: showWordByWord ?? this.showWordByWord,
      themeMode: themeMode ?? this.themeMode,
      textSize: textSize ?? this.textSize,
      readingOrder: readingOrder ?? this.readingOrder,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      plan: plan ?? this.plan,
      readingTrack: readingTrack ?? this.readingTrack,
      currentEditionId: currentEditionId ?? this.currentEditionId,
      secondaryEditionId: clearSecondaryEdition
          ? null
          : secondaryEditionId ?? this.secondaryEditionId,
      dailyReadingMinutes: dailyReadingMinutes ?? this.dailyReadingMinutes,
      celebrations: celebrations ?? this.celebrations,
      readingLayout: readingLayout ?? this.readingLayout,
    );
  }
}
