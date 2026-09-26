import 'package:meta/meta.dart';

import '../entities/notification_preferences.dart';
import '../entities/reminder_message.dart';
import '../entities/reminder_readiness.dart';

// `NotificationPermissionStatus` and the requirements it describes are domain
// values, not implementation details, so they live with the entities. Re-
// exported here because everything that talks to a scheduler needs them.
export '../entities/reminder_message.dart';
export '../entities/reminder_readiness.dart';

/// Which reminder a notification was: the Daily Ayah's, or a reading plan's.
enum ReminderKind {
  /// The Daily Ayah reminder. Opening it opens the ayah, and counts as
  /// reading it.
  daily,

  /// A reading plan's reminder. Opening it shows the day's goal first, and
  /// reads nothing on the reader's behalf.
  plan,
}

/// Where a tapped notification should take the reader.
@immutable
class QuranDeepLink {
  const QuranDeepLink({
    required this.editionId,
    this.kind = ReminderKind.daily,
  });

  /// The edition the reminder was for. The reader is taken to their current
  /// position in it — never to an ayah chosen by the notification itself.
  final String editionId;

  final ReminderKind kind;

  @override
  bool operator ==(Object other) =>
      other is QuranDeepLink &&
      other.editionId == editionId &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(editionId, kind);
}

/// Everything the app needs from the platform's local-notification support.
///
/// Scheduling is deliberately one-way: firing a notification never changes
/// reading progress. What a reminder *says* is not decided here — the message
/// arrives already composed, so this layer knows nothing about ayat, editions
/// or plans and cannot leak more than the reader asked it to.
abstract interface class NotificationScheduler {
  /// Prepares the plugin and timezone database. Safe to call more than once.
  Future<void> initialize();

  /// What the operating system is currently allowing.
  ///
  /// Re-read on every resume, because the reader may have changed any of it in
  /// system settings while the app was in the background.
  Future<ReminderReadiness> readiness();

  /// Raises the operating system's own prompt for [requirement] and reports
  /// whether it ended up granted.
  ///
  /// Only called once the reader has asked for reminders, so every prompt
  /// arrives with a reason the reader has already agreed to. Requirements the
  /// platform does not have return true — there is nothing to withhold.
  Future<bool> request(ReminderRequirement requirement);

  /// Opens this app's page in the system's notification settings.
  ///
  /// The escape hatch for a permission the OS will no longer prompt for: once
  /// notifications have been refused, [request] returns false without showing
  /// anything, and system settings is the only way back.
  ///
  /// Returns false when the platform could not open it.
  Future<bool> openSystemNotificationSettings();

  /// Cancels everything pending and re-arms from [preferences], showing
  /// [message], along with each of [planReminders].
  ///
  /// The two are independent: the Daily Ayah reminder follows [preferences]
  /// and may be off while a plan's reminders are on, or the other way round.
  ///
  /// Called whenever preferences change and on every app start, which is what
  /// keeps reminders correct across reboots, app updates, DST transitions and
  /// the reader travelling to a new timezone.
  ///
  /// [message] is a snapshot, not a subscription: an OS-level repeating alarm
  /// carries fixed text, so a reminder that names an ayah names the one that
  /// was next when it was armed. Re-arming after progress changes is what keeps
  /// that honest, and is why the app re-arms on reading as well as on launch.
  Future<void> reschedule({
    required NotificationPreferences preferences,
    required String? editionId,
    ReminderMessage message = ReminderMessage.invitation,
    List<PlanReminder> planReminders = const <PlanReminder>[],
  });

  Future<void> cancelAll();

  /// The notification that launched the app, if any. Consumed once.
  Future<QuranDeepLink?> consumeLaunchDeepLink();

  /// Deep links from notifications tapped while the app is running.
  Stream<QuranDeepLink> get deepLinks;

  /// How many reminders the OS currently has armed for this app.
  ///
  /// Diagnostic only — the settings screen previews *upcoming* times from
  /// [ReminderSchedule], which is exact and does not depend on the platform.
  Future<int> pendingCount();
}
