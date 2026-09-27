import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/entities/enums.dart';
import '../../domain/entities/notification_preferences.dart';
import '../../domain/repositories/notification_scheduler.dart';
import '../../domain/services/reminder_schedule.dart';
import 'device_power_settings.dart';

/// Handles a notification tapped while the app was terminated or in the
/// background. Must be a top-level function so the platform can find it.
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  // Nothing to do here: the tap is delivered again through
  // `getNotificationAppLaunchDetails` when the UI isolate starts, and reading
  // progress must never change without the reader opening the ayah.
}

/// [NotificationScheduler] backed by `flutter_local_notifications`.
///
/// ## How reminders stay correct
///
/// Times are stored as wall-clock values and resolved against the device's
/// *current* timezone every time we schedule, so travelling or a DST change
/// keeps 8:00 AM at 8:00 AM.
///
/// Daily, weekly and selected-day cadences are armed as OS-level repeating
/// notifications — one per reminder time of the day — which survive reboots
/// and app updates without the app running. Every-other-day has no repeating
/// equivalent, so a rolling window of concrete occurrences is armed instead and
/// topped up on each app start.
///
/// Once the day's ayah has been read, a repeating reminder is simply armed to
/// *start* at its next occurrence after the quiet period, rather than now: it
/// skips the rest of today and carries on repeating from there.
///
/// ## How reminders stay punctual
///
/// Android only guarantees a reminder lands at the chosen minute when the app
/// is allowed to schedule *exact* alarms. Without that permission the OS may
/// hold it back until the device next wakes, which under Doze can be hours. So
/// every reschedule asks the platform what it is currently allowed to do and
/// picks the most accurate mode available, rather than assuming one. Losing the
/// permission downgrades a reminder; it never cancels it.
class LocalNotificationScheduler implements NotificationScheduler {
  LocalNotificationScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    this._power = const DevicePowerSettings(),
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final DevicePowerSettings _power;
  final StreamController<QuranDeepLink> _deepLinks =
      StreamController<QuranDeepLink>.broadcast();

  bool _initialized = false;
  bool _launchLinkConsumed = false;

  static const String channelId = 'daily_quran_reminders';
  static const String channelName = 'Reading reminders';
  static const String channelDescription =
      'A gentle prompt when your next ayah is ready to read.';

  /// A plan's reminders have a channel of their own, so a reader can quiet one
  /// in system settings without losing the other.
  static const String planChannelId = 'daily_quran_plan';
  static const String planChannelName = 'Plan reminders';
  static const String planChannelDescription =
      'Your reading plan’s goal for the day.';

  /// Repeating reminders occupy 1000-1047: ten ids for each of the day's
  /// reminder times, the first of them for a daily reminder and the next seven
  /// for weekly / selected-day ones (one per ISO weekday).
  static const int _repeatingIdBase = 1000;
  static const int _idsPerTime = 10;

  /// Every-other-day occurrences occupy 1100 upwards.
  static const int _intervalIdBase = 1100;

  /// How many every-other-day reminders to keep armed — roughly two months at
  /// one a day, fewer days at more — re-armed whenever the app runs.
  static const int _intervalWindow = 30;

  /// A plan's day-by-day reminders occupy 2000 upwards.
  static const int _planIdBase = 2000;

  /// Body length past which a notification is made expandable rather than
  /// truncated. Comfortably longer than any invitation or citation, so only the
  /// settings that carry actual text cross it.
  static const int _expandableAfter = 48;

  @override
  Stream<QuranDeepLink> get deepLinks => _deepLinks.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    await _initializeTimezone();

    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // All three permission requests are off: the OS prompt is raised later,
    // once the reader has picked a reminder time and knows why we are asking.
    const DarwinInitializationSettings darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: _handleResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );

    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.defaultImportance,
      ),
    );
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        planChannelId,
        planChannelName,
        description: planChannelDescription,
        importance: Importance.defaultImportance,
      ),
    );

    _initialized = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

  /// Loads the timezone database and points it at the device's zone.
  ///
  /// Called on every [initialize] and every [reschedule] so a device that
  /// changed timezone is picked up without a reinstall. Falls back to UTC
  /// rather than throwing — a reminder at the wrong hour beats a crash.
  Future<void> _initializeTimezone() async {
    tz_data.initializeTimeZones();
    try {
      final String name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } on Object catch (error) {
      debugPrint('Daily Quran: falling back to UTC for reminders ($error)');
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  }

  void _handleResponse(NotificationResponse response) {
    final QuranDeepLink? link = _parsePayload(response.payload);
    if (link != null) _deepLinks.add(link);
  }

  @override
  Future<ReminderReadiness> readiness() async {
    await initialize();

    final AndroidFlutterLocalNotificationsPlugin? android = _android;
    if (android != null) {
      // Android cannot distinguish "never asked" from "refused" — both read as
      // not enabled. Reporting `denied` is the honest summary, and the UI still
      // asks first, falling back to system settings only once a prompt has
      // actually come back empty-handed.
      return ReminderReadiness(
        notifications: _statusOf(await android.areNotificationsEnabled()),
        exactTiming: _statusOf(await android.canScheduleExactNotifications()),
        background: _statusOf(await _power.isExemptFromBatteryOptimisation()),
      );
    }

    final IOSFlutterLocalNotificationsPlugin? ios = _ios;
    if (ios != null) {
      final NotificationsEnabledOptions? options = await ios.checkPermissions();
      return ReminderReadiness(
        notifications: options == null
            ? NotificationPermissionStatus.notDetermined
            : _statusOf(options.isEnabled),
        // iOS schedules and delivers reminders itself: there is no alarm
        // permission and no battery exemption to ask for.
        exactTiming: NotificationPermissionStatus.unsupported,
        background: NotificationPermissionStatus.unsupported,
      );
    }

    return ReminderReadiness.unsupported;
  }

  /// A platform answer of yes, no, or "cannot say" as a status. Cannot say
  /// means the OS has no such control, so there is nothing to prompt for.
  static NotificationPermissionStatus _statusOf(bool? allowed) {
    if (allowed == null) return NotificationPermissionStatus.unsupported;
    return allowed
        ? NotificationPermissionStatus.granted
        : NotificationPermissionStatus.denied;
  }

  @override
  Future<bool> request(ReminderRequirement requirement) async {
    await initialize();

    switch (requirement) {
      case ReminderRequirement.notifications:
        final AndroidFlutterLocalNotificationsPlugin? android = _android;
        if (android != null) {
          return await android.requestNotificationsPermission() ?? false;
        }
        final IOSFlutterLocalNotificationsPlugin? ios = _ios;
        if (ios != null) {
          return await ios.requestPermissions(
                alert: true,
                badge: true,
                sound: true,
              ) ??
              false;
        }
        return false;

      case ReminderRequirement.exactTiming:
        // Sends the reader to the system's "Alarms & reminders" screen and
        // reports what they chose on the way back.
        final AndroidFlutterLocalNotificationsPlugin? android = _android;
        if (android != null) {
          return await android.requestExactAlarmsPermission() ?? false;
        }
        // Nothing to ask for: already as punctual as the platform allows.
        return true;

      case ReminderRequirement.background:
        if (_android == null) return true;
        return _power.requestBatteryOptimisationExemption();
    }
  }

  @override
  Future<bool> openSystemNotificationSettings() =>
      _power.openNotificationSettings();

  @override
  Future<void> cancelAll() async {
    await initialize();
    await _plugin.cancelAll();
  }

  @override
  Future<void> reschedule({
    required NotificationPreferences preferences,
    required String? editionId,
    ReminderMessage message = ReminderMessage.invitation,
    List<PlanReminder> planReminders = const <PlanReminder>[],
    DateTime? quietUntil,
  }) async {
    await initialize();
    // Re-resolve the device zone: this is the moment a timezone change or a
    // DST boundary gets picked up.
    await _initializeTimezone();

    // Always start from a clean slate so a frequency change can never leave a
    // stale reminder armed.
    await _plugin.cancelAll();

    if (!preferences.enabled && planReminders.isEmpty) return;

    final ReminderReadiness current = await readiness();
    if (current.isBlocked) return;

    // Exact where the OS allows it, approximate where it does not. Both survive
    // Doze; only the exact one promises the minute the reader chose.
    final AndroidScheduleMode mode =
        current.exactTiming == NotificationPermissionStatus.granted
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle;

    // Whatever the reader chose to have revealed, composed upstream. This layer
    // does not decide it and cannot widen it: by default it is an invitation
    // with nothing in it, and it never names the translation — which edition is
    // being read is the reader's business, not a notification's.
    final String title = message.title;
    final String body = message.body;
    final String payload = jsonEncode(<String, Object?>{
      'type': _dailyType,
      'editionId': editionId,
    });

    await _schedulePlan(planReminders, editionId: editionId, mode: mode);

    if (!preferences.enabled) return;

    final List<TimeOfDayValue> times = preferences.times;
    switch (preferences.frequency) {
      case NotificationFrequency.daily:
        for (int slot = 0; slot < times.length; slot++) {
          await _scheduleRepeating(
            id: _repeatingIdBase + slot * _idsPerTime,
            first: _nextInstanceOfTime(times[slot], notBefore: quietUntil),
            match: DateTimeComponents.time,
            mode: mode,
            title: title,
            body: body,
            payload: payload,
          );
        }
      case NotificationFrequency.selectedDays:
      case NotificationFrequency.weekly:
        final Set<int> weekdays = ReminderSchedule(preferences).activeWeekdays;
        for (int slot = 0; slot < times.length; slot++) {
          for (final int weekday in weekdays) {
            await _scheduleRepeating(
              id: _repeatingIdBase + slot * _idsPerTime + weekday,
              first: _nextInstanceOfWeekday(
                weekday,
                times[slot],
                notBefore: quietUntil,
              ),
              match: DateTimeComponents.dayOfWeekAndTime,
              mode: mode,
              title: title,
              body: body,
              payload: payload,
            );
          }
        }
      case NotificationFrequency.everyOtherDay:
        // No repeating rule matches "every other day", so a window of concrete
        // occurrences is armed and topped up whenever the app runs.
        final List<DateTime> occurrences =
            ReminderSchedule(preferences).upcomingReminders(
          DateTime.now(),
          count: _intervalWindow,
          notBefore: quietUntil,
        );
        for (int index = 0; index < occurrences.length; index++) {
          await _scheduleRepeating(
            id: _intervalIdBase + index,
            first: _toTz(occurrences[index]),
            match: null,
            mode: mode,
            title: title,
            body: body,
            payload: payload,
          );
        }
    }
  }

  /// Arms a plan's reminders, one concrete day each.
  ///
  /// Never repeating: each carries the goal as it will stand on its own day,
  /// and the next launch re-arms the lot from the reading as it then stands.
  Future<void> _schedulePlan(
    List<PlanReminder> reminders, {
    required String? editionId,
    required AndroidScheduleMode mode,
  }) async {
    if (reminders.isEmpty) return;
    final String payload = jsonEncode(<String, Object?>{
      'type': _planType,
      'editionId': editionId,
    });
    final DateTime now = DateTime.now();
    for (int index = 0; index < reminders.length; index++) {
      final PlanReminder reminder = reminders[index];
      // Composed a moment ago; a reminder due in that moment has already gone.
      if (!reminder.at.isAfter(now)) continue;
      await _scheduleRepeating(
        id: _planIdBase + index,
        first: _toTz(reminder.at),
        match: null,
        mode: mode,
        title: reminder.message.title,
        body: reminder.message.body,
        payload: payload,
        forPlan: true,
      );
    }
  }

  Future<void> _scheduleRepeating({
    required int id,
    required tz.TZDateTime first,
    required DateTimeComponents? match,
    required AndroidScheduleMode mode,
    required String title,
    required String body,
    required String payload,
    bool forPlan = false,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        first,
        NotificationDetails(
          android: AndroidNotificationDetails(
            forPlan ? planChannelId : channelId,
            forPlan ? planChannelName : channelName,
            channelDescription:
                forPlan ? planChannelDescription : channelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            // A one-line body is left as one line. A reader who asked for the
            // ayah's text gets it expandable instead, because Android would
            // otherwise cut a translation off mid-sentence — which is a worse
            // way to show scripture than not showing it at all. Both disable
            // HTML parsing, so the text is rendered exactly as it is stored.
            styleInformation: body.length > _expandableAfter
                ? BigTextStyleInformation(
                    body,
                    htmlFormatBigText: false,
                    contentTitle: title,
                    htmlFormatContentTitle: false,
                  )
                : const DefaultStyleInformation(false, false),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
        ),
        androidScheduleMode: mode,
        payload: payload,
        matchDateTimeComponents: match,
      );
    } on PlatformException catch (error) {
      // The exact-alarm permission can be withdrawn between the check above and
      // the call itself, and Android throws rather than quietly downgrading. An
      // approximate reminder is worth far more than none.
      if (mode != AndroidScheduleMode.exactAllowWhileIdle) rethrow;
      debugPrint(
        'Daily Quran: exact alarm refused (${error.code}); '
        'falling back to an approximate reminder.',
      );
      await _scheduleRepeating(
        id: id,
        first: first,
        match: match,
        mode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
        payload: payload,
        forPlan: forPlan,
      );
    }
  }

  @override
  Future<QuranDeepLink?> consumeLaunchDeepLink() async {
    if (_launchLinkConsumed) return null;
    _launchLinkConsumed = true;
    await initialize();
    final NotificationAppLaunchDetails? details =
        await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return _parsePayload(details.notificationResponse?.payload);
  }

  @override
  Future<int> pendingCount() async {
    await initialize();
    final List<PendingNotificationRequest> pending =
        await _plugin.pendingNotificationRequests();
    return pending.length;
  }

  static const String _dailyType = 'reminder';
  static const String _planType = 'plan';

  static QuranDeepLink? _parsePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(payload);
      if (decoded is! Map<String, Object?>) return null;
      final Object? editionId = decoded['editionId'];
      if (editionId is! String || editionId.isEmpty) return null;
      return QuranDeepLink(
        editionId: editionId,
        // Anything not recognisably a plan's is treated as the Daily Ayah's,
        // which is what every reminder armed before plans existed was.
        kind: decoded['type'] == _planType
            ? ReminderKind.plan
            : ReminderKind.daily,
      );
    } on FormatException {
      return null;
    }
  }

  static tz.TZDateTime _toTz(DateTime value) => tz.TZDateTime(
        tz.local,
        value.year,
        value.month,
        value.day,
        value.hour,
        value.minute,
      );

  /// The next [time] from now, and not before [notBefore] when that is given.
  ///
  /// [notBefore] is a wall-clock moment, compared field by field rather than
  /// as an instant, for the same reason reminder times are stored that way.
  static tz.TZDateTime _nextInstanceOfTime(
    TimeOfDayValue time, {
    DateTime? notBefore,
  }) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    // Bounded: a quiet period is never more than a week or so long, but a
    // corrupt one must not spin here.
    for (int guard = 0; guard < 400; guard++) {
      final bool quiet =
          notBefore != null && _wallClock(scheduled).isBefore(notBefore);
      if (scheduled.isAfter(now) && !quiet) break;
      scheduled = _plusDays(scheduled, 1);
    }
    return scheduled;
  }

  static tz.TZDateTime _nextInstanceOfWeekday(
    int weekday,
    TimeOfDayValue time, {
    DateTime? notBefore,
  }) {
    tz.TZDateTime scheduled = _nextInstanceOfTime(time, notBefore: notBefore);
    while (scheduled.weekday != weekday) {
      scheduled = _plusDays(scheduled, 1);
    }
    return scheduled;
  }

  static DateTime _wallClock(tz.TZDateTime value) => DateTime(
        value.year,
        value.month,
        value.day,
        value.hour,
        value.minute,
      );

  /// Adds whole calendar days while holding the wall-clock time steady.
  ///
  /// Adding a [Duration] would shift the hour across a DST boundary; rebuilding
  /// the date keeps "8:00 AM" at 8:00 AM.
  static tz.TZDateTime _plusDays(tz.TZDateTime value, int days) =>
      tz.TZDateTime(
        tz.local,
        value.year,
        value.month,
        value.day + days,
        value.hour,
        value.minute,
      );

  Future<void> dispose() async => _deepLinks.close();
}
