import 'package:meta/meta.dart';

import 'enums.dart';

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
    this.currentEditionId,
  });

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

  /// The edition the Today screen reads from. Null before onboarding finishes.
  final String? currentEditionId;

  UserPreferences copyWith({
    LanguageMode? languageMode,
    bool? showTransliteration,
    bool? showWordByWord,
    AppThemeMode? themeMode,
    TextSizePreference? textSize,
    ReadingOrder? readingOrder,
    bool? onboardingComplete,
    String? currentEditionId,
  }) {
    return UserPreferences(
      languageMode: languageMode ?? this.languageMode,
      showTransliteration: showTransliteration ?? this.showTransliteration,
      showWordByWord: showWordByWord ?? this.showWordByWord,
      themeMode: themeMode ?? this.themeMode,
      textSize: textSize ?? this.textSize,
      readingOrder: readingOrder ?? this.readingOrder,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      currentEditionId: currentEditionId ?? this.currentEditionId,
    );
  }
}
