import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/repositories/notification_scheduler.dart';
import '../features/planner/plan_status.dart';
import 'providers.dart';

/// One-time startup work, run behind the splash screen.
///
/// Re-arming reminders here is what makes them survive a device restart, an app
/// update, a daylight-saving change or the reader flying somewhere new: on
/// every launch the schedule is rebuilt from the saved preferences against the
/// device's current timezone.
///
/// It never throws. If notifications are unavailable the app must still open
/// and read.
final FutureProvider<BootstrapResult> bootstrapProvider =
    FutureProvider<BootstrapResult>((Ref ref) async {
  final NotificationScheduler scheduler =
      ref.read(notificationSchedulerProvider);

  // Before anything reads the plan's track, and before its reminders are
  // armed from it.
  await carryOverLegacyPlan(ref);

  QuranDeepLink? launchLink;
  try {
    await scheduler.initialize();
    launchLink = await scheduler.consumeLaunchDeepLink();
    await ref.read(notificationPreferencesProvider.notifier).applyToScheduler();
  } on Object catch (error, stack) {
    // Reading is the product; reminders are an accessory. A scheduling failure
    // is logged and the app continues.
    debugPrint('Daily Quran: notification setup failed: $error\n$stack');
  }

  return BootstrapResult(launchDeepLink: launchLink);
});

@immutable
class BootstrapResult {
  const BootstrapResult({this.launchDeepLink});

  /// Set when the app was launched by tapping a reminder.
  final QuranDeepLink? launchDeepLink;
}

/// Notification taps that arrive while the app is already running.
final StreamProvider<QuranDeepLink> deepLinkStreamProvider =
    StreamProvider<QuranDeepLink>(
  (Ref ref) => ref.watch(notificationSchedulerProvider).deepLinks,
);
