/// Every location in the app, in one place.
///
/// Plain strings rather than generated typed routes: the route set is small,
/// and keeping it dependency-free means notification payloads and tests can
/// build locations without pulling in code generation.
abstract final class Routes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';

  static const String today = '/today';
  static const String library = '/library';
  static const String favourites = '/favourites';
  static const String progress = '/progress';
  static const String settings = '/settings';

  static const String editionSegment = 'edition';

  /// Details for one edition.
  static String edition(String editionId) =>
      '$library/$editionSegment/${Uri.encodeComponent(editionId)}';

  static const String settingsNotifications = '$settings/notifications';
  static const String settingsReading = '$settings/reading';
  static const String settingsSecondTranslation = '$settings/second-translation';
  static const String settingsAppearance = '$settings/appearance';
  static const String settingsAbout = '$settings/about';

  /// The Qur'an Planner. Lives under Progress, beside the readings it plans.
  static const String planner = '$progress/plan';

  /// Today's goal for the reader's plan — where the plan's reminder opens.
  /// Outside the tabs, so nothing competes with the one thing it asks.
  static const String planGoal = '/goal';

  /// Tab order for the bottom navigation bar.
  static const List<String> tabs = <String>[
    today,
    library,
    favourites,
    progress,
    settings,
  ];
}
