import 'package:daily_quran/data/local/preferences_store.dart';
import 'package:daily_quran/domain/entities/notification_preferences.dart';
import 'package:daily_quran/domain/entities/reading_plan.dart';
import 'package:daily_quran/domain/entities/user_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reminder times, reading time and celebrations survive a restart, and
/// whatever was stored before them reads back as it always did.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PreferencesStore> store([
    Map<String, Object> values = const <String, Object>{},
  ]) async {
    SharedPreferences.setMockInitialValues(values);
    return PreferencesStore(await SharedPreferences.getInstance());
  }

  test('several reminder times are kept, earliest first', () async {
    final PreferencesStore first = await store();
    await first.saveNotificationPreferences(
      NotificationPreferences.defaults.withTimes(const <TimeOfDayValue>[
        TimeOfDayValue(21, 0),
        TimeOfDayValue(6, 15),
      ]),
    );

    final NotificationPreferences loaded =
        await first.loadNotificationPreferences();

    expect(loaded.time, const TimeOfDayValue(6, 15));
    expect(loaded.laterTimes, const <TimeOfDayValue>[TimeOfDayValue(21, 0)]);
  });

  test('a reader from before has one reminder, as they did', () async {
    final PreferencesStore old = await store(<String, Object>{
      'flutter.notify.enabled': true,
      'flutter.notify.time': '07:30',
    });

    final NotificationPreferences loaded = await old.loadNotificationPreferences();

    expect(loaded.times, const <TimeOfDayValue>[TimeOfDayValue(7, 30)]);
  });

  test('a stored later time before the first is put back in order', () async {
    final PreferencesStore edited = await store(<String, Object>{
      'flutter.notify.time': '20:00',
      'flutter.notify.later_times': <String>['06:00', 'nonsense'],
    });

    final NotificationPreferences loaded =
        await edited.loadNotificationPreferences();

    expect(loaded.time, const TimeOfDayValue(6, 0));
    expect(loaded.laterTimes, const <TimeOfDayValue>[TimeOfDayValue(20, 0)]);
  });

  test('a plan’s reminder times, reading time and celebrations are kept',
      () async {
    final PreferencesStore first = await store();
    await first.saveUserPreferences(
      UserPreferences.defaults.copyWith(
        plan: ReadingPlan(
          kind: ReadingPlanKind.oneYear,
          startedOn: DateTime(2026, 1, 1),
        ).withReminderTimes(const <TimeOfDayValue>[
          TimeOfDayValue(7, 0),
          TimeOfDayValue(19, 0),
        ]),
        dailyReadingMinutes: 15,
        celebrations: false,
      ),
    );

    final UserPreferences loaded = await first.loadUserPreferences();

    expect(loaded.plan.reminderTimes, const <TimeOfDayValue>[
      TimeOfDayValue(7, 0),
      TimeOfDayValue(19, 0),
    ]);
    expect(loaded.dailyReadingMinutes, 15);
    expect(loaded.celebrations, isFalse);
  });

  test('a reader from before has no reading time and celebrations on',
      () async {
    final UserPreferences loaded = await (await store()).loadUserPreferences();

    expect(loaded.dailyReadingMinutes, 0);
    expect(loaded.celebrations, isTrue);
  });

  test('a reading time the app does not offer reads as none', () async {
    final UserPreferences loaded = await (await store(<String, Object>{
      'flutter.pref.daily_reading_minutes': 7,
    }))
        .loadUserPreferences();

    expect(loaded.dailyReadingMinutes, 0);
  });
}
