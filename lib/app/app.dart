import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/entities/enums.dart';
import '../domain/entities/user_preferences.dart';
import '../domain/repositories/notification_scheduler.dart';
import '../features/today/today_controller.dart';
import '../shared/theme/app_theme.dart';
import 'bootstrap.dart';
import 'providers.dart';
import 'router.dart';
import 'routes.dart';

/// Application root.
///
/// Beyond building the [MaterialApp] it owns two cross-cutting behaviours:
/// following notification taps to the right edition, and refreshing when the
/// app comes back to the foreground.
class DailyQuranApp extends ConsumerStatefulWidget {
  const DailyQuranApp({super.key});

  @override
  ConsumerState<DailyQuranApp> createState() => _DailyQuranAppState();
}

class _DailyQuranAppState extends ConsumerState<DailyQuranApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Leaving the app is the moment a reminder has to be re-armed. An OS
      // alarm carries fixed text, so one that names an ayah — or counts out a
      // plan's portion — would otherwise still be describing the reading as it
      // stood when the app last started. Doing it here, rather than after every
      // ayah, keeps it to once a session.
      ref.read(notificationPreferencesProvider.notifier).applyToScheduler();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    // The reader may have changed notification permission in system settings,
    // and enough time may have passed for the reading to move on.
    ref.invalidate(reminderReadinessProvider);
    ref.read(todayControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final GoRouter router = ref.watch(routerProvider);
    final AppThemeMode themeMode = ref.watch(
      userPreferencesProvider.select((UserPreferences prefs) => prefs.themeMode),
    );

    // A reminder tapped while the app was terminated.
    ref.listen(bootstrapProvider, (
      AsyncValue<BootstrapResult>? previous,
      AsyncValue<BootstrapResult> next,
    ) {
      final QuranDeepLink? link = next.value?.launchDeepLink;
      if (link != null) _openFromReminder(link);
    });

    // A permission granted or withdrawn in system settings while the app was in
    // the background.
    //
    // Reminders are armed as exact alarms only where the OS allows it, and the
    // mode is fixed at the moment they are scheduled. So a reader who turns
    // "Alarms & reminders" on and comes back needs them armed again — otherwise
    // they fix the setting and nothing changes until the next cold start.
    ref.listen(reminderReadinessProvider, (
      AsyncValue<ReminderReadiness>? previous,
      AsyncValue<ReminderReadiness> next,
    ) {
      final ReminderReadiness? before = previous?.value;
      final ReminderReadiness? after = next.value;
      if (before == null || after == null || before == after) return;
      ref.read(notificationPreferencesProvider.notifier).applyToScheduler();
    });

    // A reminder that names an ayah cannot be composed until an edition's text
    // is actually in local storage — and startup arms reminders before the
    // first install has happened, so on a first launch there is nothing to
    // name. This re-arms once there is.
    //
    // Only for readers who asked for the ayah to be named: on the default
    // setting the text is fixed, and re-arming would be a cancel-and-schedule
    // for no change at all.
    ref.listen(todayControllerProvider, (
      AsyncValue<TodayState>? previous,
      AsyncValue<TodayState> next,
    ) {
      if (previous?.value?.ayah != null || next.value?.ayah == null) return;
      if (ref.read(notificationPreferencesProvider).content ==
          ReminderContent.invitation) {
        return;
      }
      ref.read(notificationPreferencesProvider.notifier).applyToScheduler();
    });

    // A reminder tapped while the app was running.
    ref.listen(deepLinkStreamProvider, (
      AsyncValue<QuranDeepLink>? previous,
      AsyncValue<QuranDeepLink> next,
    ) {
      final QuranDeepLink? link = next.value;
      if (link != null) _openFromReminder(link);
    });

    return MaterialApp.router(
      title: 'Daily Quran',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      builder: (BuildContext context, Widget? child) {
        // Respect the platform's dynamic type, but keep it inside a range the
        // reading layout can still honour.
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.6,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  /// Follows a tapped reminder.
  ///
  /// The Daily Ayah's reminder opens the ayah and marks it read: the
  /// notification firing changed nothing, but the reader actually opening it
  /// is what counts as reading it.
  ///
  /// A plan's reminder opens the day's goal instead, and marks nothing. A
  /// goal of two hundred ayat is not read by tapping a notification — the
  /// reader sees what the day asks, and begins when they choose to.
  Future<void> _openFromReminder(QuranDeepLink link) async {
    final String? currentId = ref.read(userPreferencesProvider).currentEditionId;
    if (link.editionId != currentId) {
      await ref
          .read(userPreferencesProvider.notifier)
          .setCurrentEdition(link.editionId);
    }

    if (link.kind == ReminderKind.plan) {
      // A plan stopped since the reminder was armed has no goal to show.
      final bool hasPlan = ref.read(userPreferencesProvider).plan.isPaced;
      ref.read(routerProvider).go(hasPlan ? Routes.planGoal : Routes.today);
      // The day may have turned since the goal was last worked out.
      await ref.read(todayControllerProvider.notifier).refresh();
      return;
    }

    ref.read(routerProvider).go(Routes.today);
    await ref.read(todayControllerProvider.notifier).markReadFromNotification();
  }
}
