import '../../core/utils/formatting.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/notification_preferences.dart';
import '../../domain/entities/reading_plan.dart';
import '../../domain/entities/reminder_readiness.dart';

/// Human-readable names for preference values. Kept in one place so the
/// settings hub and the detail screens can never drift apart.
abstract final class SettingsLabels {
  static String language(LanguageMode mode) {
    switch (mode) {
      case LanguageMode.translation:
        return 'Translation';
      case LanguageMode.arabic:
        return 'Arabic';
      case LanguageMode.both:
        return 'Arabic + translation';
    }
  }

  static String theme(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return 'System';
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
    }
  }

  static String textSize(TextSizePreference size) {
    switch (size) {
      case TextSizePreference.small:
        return 'Small';
      case TextSizePreference.standard:
        return 'Default';
      case TextSizePreference.large:
        return 'Large';
      case TextSizePreference.extraLarge:
        return 'Extra large';
    }
  }

  static String planName(ReadingPlanKind kind) {
    switch (kind) {
      case ReadingPlanKind.oneAyah:
        return 'One ayah a day';
      case ReadingPlanKind.oneMonth:
        return 'In a month';
      case ReadingPlanKind.oneYear:
        return 'In a year';
      case ReadingPlanKind.custom:
        return 'By a chosen date';
    }
  }

  /// The plan as a settings-row value — a chosen-date plan is named by its
  /// date, which is the whole of what the reader chose.
  static String planValue(ReadingPlan plan) {
    final DateTime? target = plan.targetDate;
    if (plan.kind == ReadingPlanKind.custom && target != null) {
      return 'By ${Formatting.date(target)}';
    }
    return planName(plan.kind);
  }

  /// What a reminder will say, as the example itself rather than a description
  /// of one — the reader is choosing what appears on their lock screen, so the
  /// most useful thing to show them is the text.
  static String reminderContentName(ReminderContent content) {
    switch (content) {
      case ReminderContent.invitation:
        return 'Just an invitation';
      case ReminderContent.reference:
        return 'Which ayah is next';
      case ReminderContent.translation:
        return 'The translation';
      case ReminderContent.arabic:
        return 'The Arabic';
    }
  }

  static String reminderContentExample(ReminderContent content) {
    switch (content) {
      case ReminderContent.invitation:
        return '“Your next ayah is ready.”';
      case ReminderContent.reference:
        return '“Al-Baqarah 2:255” — the citation only, no Qur’an text.';
      case ReminderContent.translation:
        return '“Allah — there is no deity except Him…” on your lock screen.';
      case ReminderContent.arabic:
        return 'The ayah’s Arabic on your lock screen.';
    }
  }

  static String frequencyName(NotificationFrequency frequency) {
    switch (frequency) {
      case NotificationFrequency.daily:
        return 'Every day';
      case NotificationFrequency.everyOtherDay:
        return 'Every other day';
      case NotificationFrequency.selectedDays:
        return 'Selected days';
      case NotificationFrequency.weekly:
        return 'Weekly';
    }
  }

  /// Frequency including the specific days, e.g. "Selected days · Mon, Wed".
  static String frequency(NotificationPreferences preferences) {
    final String name = frequencyName(preferences.frequency);
    switch (preferences.frequency) {
      case NotificationFrequency.daily:
      case NotificationFrequency.everyOtherDay:
        return name;
      case NotificationFrequency.selectedDays:
        return '$name · ${Formatting.weekdayList(preferences.selectedWeekdays)}';
      case NotificationFrequency.weekly:
        if (preferences.selectedWeekdays.isEmpty) return name;
        final int day = preferences.selectedWeekdays.reduce(
          (int a, int b) => a < b ? a : b,
        );
        return '$name · ${Formatting.fullWeekday(day)}';
    }
  }
}

/// How the operating system's reminder permissions are described to the
/// reader. Deliberately plain: the reader is being asked to change a system
/// setting, so they are told what it does, not what it is called internally.
abstract final class ReminderRequirementLabels {
  static String name(ReminderRequirement requirement) {
    switch (requirement) {
      case ReminderRequirement.notifications:
        return 'Notifications';
      case ReminderRequirement.exactTiming:
        return 'Exact timing';
      case ReminderRequirement.background:
        return 'Unrestricted battery use';
    }
  }

  /// What the reader loses without it.
  static String reason(ReminderRequirement requirement) {
    switch (requirement) {
      case ReminderRequirement.notifications:
        return 'Without this, no reminder can reach you.';
      case ReminderRequirement.exactTiming:
        return 'Lets a reminder arrive at the minute you chose instead of '
            'whenever your phone next wakes up.';
      case ReminderRequirement.background:
        return 'Stops your phone putting the app to sleep and cancelling '
            'tomorrow’s reminder with it.';
    }
  }

  /// The value shown on the right of a settings row.
  static String status(NotificationPermissionStatus status) {
    switch (status) {
      case NotificationPermissionStatus.granted:
        return 'Allowed';
      case NotificationPermissionStatus.denied:
        return 'Not allowed';
      case NotificationPermissionStatus.notDetermined:
        return 'Not set';
      case NotificationPermissionStatus.unsupported:
        return 'Not needed';
    }
  }
}
