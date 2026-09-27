import 'package:meta/meta.dart';

import 'enums.dart';

/// Time of day, stored independently of any date so it survives timezone
/// changes: 8:00 AM means 8:00 AM wherever the reader happens to be.
@immutable
class TimeOfDayValue implements Comparable<TimeOfDayValue> {
  const TimeOfDayValue(this.hour, this.minute);

  /// Parses `"HH:mm"`. Falls back to the default reminder time when malformed,
  /// so a corrupt preference can never break scheduling.
  factory TimeOfDayValue.parse(String? value) => tryParse(value) ?? defaultTime;

  /// Parses `"HH:mm"`, or returns null when malformed.
  static TimeOfDayValue? tryParse(String? value) {
    if (value == null) return null;
    final List<String> parts = value.split(':');
    if (parts.length != 2) return null;
    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDayValue(hour, minute);
  }

  static const TimeOfDayValue defaultTime = TimeOfDayValue(8, 0);

  final int hour;
  final int minute;

  String get storageValue =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  int get minutesFromMidnight => hour * 60 + minute;

  @override
  int compareTo(TimeOfDayValue other) =>
      minutesFromMidnight.compareTo(other.minutesFromMidnight);

  @override
  bool operator ==(Object other) =>
      other is TimeOfDayValue && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => storageValue;
}

/// A day's reminder times, as the reader set them.
abstract final class ReminderTimes {
  /// The most reminders a day can hold.
  ///
  /// Five is a day's prayers' worth, and the ceiling that keeps a full week of
  /// selected-day reminders and a plan's rolling window inside the 64 pending
  /// notifications iOS will hold: 7 × 5 + 28 = 63.
  static const int maxPerDay = 5;

  /// [times] earliest first, without repeats, and no more than [maxPerDay].
  static List<TimeOfDayValue> normalise(Iterable<TimeOfDayValue> times) {
    final List<TimeOfDayValue> sorted = times.toSet().toList()..sort();
    return sorted.length > maxPerDay ? sorted.sublist(0, maxPerDay) : sorted;
  }

  /// Parses stored `"HH:mm"` values, dropping anything malformed rather than
  /// falling back to a default — a corrupt extra reminder is simply not there.
  static List<TimeOfDayValue> parse(List<String>? values) {
    if (values == null) return const <TimeOfDayValue>[];
    return <TimeOfDayValue>[
      for (final String value in values) ?TimeOfDayValue.tryParse(value),
    ];
  }

  static List<String> toStorage(List<TimeOfDayValue> times) => <String>[
        for (final TimeOfDayValue time in times) time.storageValue,
      ];
}

/// Reminder settings. Times are wall-clock; the scheduler resolves them
/// against the device's *current* timezone every time it schedules.
@immutable
class NotificationPreferences {
  const NotificationPreferences({
    required this.enabled,
    required this.frequency,
    required this.selectedWeekdays,
    required this.time,
    this.laterTimes = const <TimeOfDayValue>[],
    this.content = ReminderContent.invitation,
    this.timezone,
    this.anchorDate,
  });

  static const NotificationPreferences defaults = NotificationPreferences(
    enabled: false,
    frequency: NotificationFrequency.daily,
    selectedWeekdays: <int>{1, 2, 3, 4, 5, 6, 7},
    time: TimeOfDayValue.defaultTime,
  );

  /// Whether the reader has asked for reminders. Independent of whether the OS
  /// currently permits them.
  final bool enabled;

  final NotificationFrequency frequency;

  /// ISO weekdays (Mon = 1 … Sun = 7) used by
  /// [NotificationFrequency.selectedDays] and [NotificationFrequency.weekly].
  final Set<int> selectedWeekdays;

  /// The first reminder of the day, and where the Daily Ayah's reading period
  /// begins: the reading moves on to the next ayah here, and nowhere else.
  final TimeOfDayValue time;

  /// Further reminders on the same day, after [time].
  ///
  /// Nudges, not new readings. Each invites the reader back to the ayah [time]
  /// brought, and is skipped once that ayah has been read — so three reminders
  /// a day still means one ayah a day, and nobody is reminded of reading they
  /// have already done.
  final List<TimeOfDayValue> laterTimes;

  /// Every reminder of the day, earliest first.
  List<TimeOfDayValue> get times =>
      ReminderTimes.normalise(<TimeOfDayValue>[time, ...laterTimes]);

  /// How much of the reading a reminder is allowed to reveal.
  ///
  /// Defaults to revealing nothing, because a notification is read on a lock
  /// screen by whoever is looking at it. Only the reader can decide that
  /// tradeoff, so only the reader changes it.
  final ReminderContent content;

  /// The IANA zone last used to schedule. Recorded only so the app can notice
  /// the device moved and reschedule; it is never used to override the device.
  final String? timezone;

  /// Reference day for [NotificationFrequency.everyOtherDay], so the cadence
  /// stays stable across reschedules.
  final DateTime? anchorDate;

  NotificationPreferences copyWith({
    bool? enabled,
    NotificationFrequency? frequency,
    Set<int>? selectedWeekdays,
    TimeOfDayValue? time,
    List<TimeOfDayValue>? laterTimes,
    ReminderContent? content,
    String? timezone,
    DateTime? anchorDate,
  }) {
    return NotificationPreferences(
      enabled: enabled ?? this.enabled,
      frequency: frequency ?? this.frequency,
      selectedWeekdays: selectedWeekdays ?? this.selectedWeekdays,
      time: time ?? this.time,
      laterTimes: laterTimes ?? this.laterTimes,
      content: content ?? this.content,
      timezone: timezone ?? this.timezone,
      anchorDate: anchorDate ?? this.anchorDate,
    );
  }

  /// These preferences with [times] as the day's reminders.
  ///
  /// The earliest becomes [time], so the reading day always begins with the
  /// first reminder of it whatever order the times were added in. An empty
  /// list changes nothing: a reminder that is on must have a time to arrive.
  NotificationPreferences withTimes(Iterable<TimeOfDayValue> times) {
    final List<TimeOfDayValue> all = ReminderTimes.normalise(times);
    if (all.isEmpty) return this;
    return copyWith(time: all.first, laterTimes: all.sublist(1));
  }

  /// The weekdays a reminder can actually land on, given [frequency].
  Set<int> get effectiveWeekdays {
    switch (frequency) {
      case NotificationFrequency.daily:
      case NotificationFrequency.everyOtherDay:
        return const <int>{1, 2, 3, 4, 5, 6, 7};
      case NotificationFrequency.selectedDays:
      case NotificationFrequency.weekly:
        return selectedWeekdays;
    }
  }
}
