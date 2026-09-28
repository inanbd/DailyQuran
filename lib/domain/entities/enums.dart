/// Which language(s) of an ayah to render.
enum LanguageMode {
  translation('translation'),
  arabic('arabic'),
  both('both');

  const LanguageMode(this.storageKey);

  final String storageKey;

  bool get showsArabic => this != LanguageMode.translation;
  bool get showsTranslation => this != LanguageMode.arabic;

  static LanguageMode fromStorage(String? value) {
    return LanguageMode.values.firstWhere(
      (LanguageMode mode) => mode.storageKey == value,
      orElse: () => LanguageMode.both,
    );
  }
}

/// How the Read tab moves from one ayah to the next.
enum ReadingLayout {
  /// One ayah to a page, turned by swiping the way a gallery is — or with the
  /// arrows.
  swipe('swipe'),

  /// The ayat one after another in a single column, surah after surah.
  scroll('scroll');

  const ReadingLayout(this.storageKey);

  final String storageKey;

  static ReadingLayout fromStorage(String? value) {
    return ReadingLayout.values.firstWhere(
      (ReadingLayout layout) => layout.storageKey == value,
      orElse: () => ReadingLayout.swipe,
    );
  }
}

/// Appearance preference. Mirrors [ThemeMode] but is persisted by the app.
enum AppThemeMode {
  system('system'),
  light('light'),
  dark('dark');

  const AppThemeMode(this.storageKey);

  final String storageKey;

  static AppThemeMode fromStorage(String? value) {
    return AppThemeMode.values.firstWhere(
      (AppThemeMode mode) => mode.storageKey == value,
      orElse: () => AppThemeMode.system,
    );
  }
}

/// Reading text size. Multiplies whatever the OS dynamic-type setting gives us
/// rather than replacing it, so platform accessibility settings still apply.
enum TextSizePreference {
  small('small', 0.9),
  standard('standard', 1.0),
  large('large', 1.15),
  extraLarge('extra_large', 1.3);

  const TextSizePreference(this.storageKey, this.scale);

  final String storageKey;
  final double scale;

  static TextSizePreference fromStorage(String? value) {
    return TextSizePreference.values.firstWhere(
      (TextSizePreference size) => size.storageKey == value,
      orElse: () => TextSizePreference.standard,
    );
  }
}

/// How often a reminder is delivered.
enum NotificationFrequency {
  daily('daily'),
  everyOtherDay('every_other_day'),
  selectedDays('selected_days'),
  weekly('weekly');

  const NotificationFrequency(this.storageKey);

  final String storageKey;

  static NotificationFrequency fromStorage(String? value) {
    return NotificationFrequency.values.firstWhere(
      (NotificationFrequency frequency) => frequency.storageKey == value,
      orElse: () => NotificationFrequency.daily,
    );
  }
}

/// How much of the reading a reminder is allowed to reveal.
///
/// Ordered from least to most disclosed, because that is the axis the reader is
/// actually choosing along: a notification lands on a lock screen, where anyone
/// nearby can read it. [invitation] is the default for that reason, and the
/// only value that carries nothing about the reading at all.
enum ReminderContent {
  /// Just an invitation to open the app. Reveals nothing.
  invitation('invitation'),

  /// The citation and the size of the portion — "Al-Baqarah 2:1 · 18 ayat".
  /// A reference, not scripture: no Qur'an text is in it.
  reference('reference'),

  /// The translation of the first ayah of the portion.
  translation('translation'),

  /// The Arabic of the first ayah of the portion.
  arabic('arabic');

  const ReminderContent(this.storageKey);

  final String storageKey;

  /// Whether this setting puts Qur'an text — Arabic or a translation of it —
  /// on the reader's lock screen.
  bool get carriesQuranText =>
      this == ReminderContent.translation || this == ReminderContent.arabic;

  static ReminderContent fromStorage(String? value) {
    return ReminderContent.values.firstWhere(
      (ReminderContent content) => content.storageKey == value,
      orElse: () => ReminderContent.invitation,
    );
  }
}

/// Order in which ayat are delivered. Only [sequential] ships in the MVP;
/// [random] exists so the scheduling code has a seam to grow into.
enum ReadingOrder {
  sequential('sequential'),
  random('random');

  const ReadingOrder(this.storageKey);

  final String storageKey;

  static ReadingOrder fromStorage(String? value) {
    return ReadingOrder.values.firstWhere(
      (ReadingOrder order) => order.storageKey == value,
      orElse: () => ReadingOrder.sequential,
    );
  }
}

/// Provenance of an edition's text. Surfaced in the UI so development
/// fixtures can never be mistaken for the Qur'an or for a real translation.
enum ContentVerification {
  /// Text comes from a verified, attributed dataset.
  verified('verified'),

  /// Placeholder text used during development. Not the Qur'an.
  developmentFixture('development_fixture');

  const ContentVerification(this.storageKey);

  final String storageKey;

  bool get isFixture => this == ContentVerification.developmentFixture;

  static ContentVerification fromStorage(String? value) {
    return ContentVerification.values.firstWhere(
      (ContentVerification status) => status.storageKey == value,
      orElse: () => ContentVerification.developmentFixture,
    );
  }
}

/// Where a surah was revealed, as classified by the source. Never inferred.
enum RevelationPlace {
  meccan('meccan', 'Meccan'),
  medinan('medinan', 'Medinan'),
  unknown('unknown', '');

  const RevelationPlace(this.storageKey, this.label);

  final String storageKey;

  /// Display name, empty when the source did not say.
  final String label;

  static RevelationPlace fromStorage(String? value) {
    final String? normalised = value?.trim().toLowerCase();
    return RevelationPlace.values.firstWhere(
      (RevelationPlace place) => place.storageKey == normalised,
      orElse: () => RevelationPlace.unknown,
    );
  }
}
