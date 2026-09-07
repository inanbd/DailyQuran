import '../entities/notification_preferences.dart';
import '../entities/reading_progress.dart';
import 'reminder_schedule.dart';

/// Decides which ayah the Today screen should show.
///
/// The rule, in one sentence: stay on what you read this period *once this
/// period's portion is finished*, otherwise move to the first ayah you have not
/// read.
///
/// On the default one-ayah plan the portion finishes the moment anything is
/// read, which is exactly the original rule — reading one ayah holds the
/// reader on it for the rest of the day. On a plan asking for eighteen, the
/// same sentence carries the reader through all eighteen and then stops.
///
/// This is what makes missed days behave gently. Nothing is ever marked read
/// because time passed or because a notification fired — a reader who skips a
/// week comes back to exactly the ayah they left unread.
abstract final class ReadingScheduler {
  /// The ordinal the Today screen opens on.
  ///
  /// [firstUnreadOrdinal] is null when every ayah has been read.
  ///
  /// [portionComplete] says whether this period's plan portion has been read.
  /// It defaults to true, which is the one-ayah behaviour: anything read this
  /// period is the whole of it.
  static int resolveTodaysOrdinal({
    required ReadingProgress progress,
    required int? firstUnreadOrdinal,
    required NotificationPreferences notificationPreferences,
    required DateTime now,
    bool portionComplete = true,
  }) {
    final int total = progress.totalAyah;
    if (total <= 0) return 1;

    // A completed reading stays on its last ayah rather than wrapping around.
    if (firstUnreadOrdinal == null) {
      return progress.currentOrdinal.clamp(1, total);
    }

    final DateTime? lastReadAt = progress.lastReadAt;
    if (lastReadAt == null) {
      // Nothing read yet: begin at the first unread ayah.
      return firstUnreadOrdinal.clamp(1, total);
    }

    final DateTime periodStart =
        ReminderSchedule(notificationPreferences).currentPeriodStart(now);

    if (lastReadAt.isBefore(periodStart)) {
      // A new reading period began since the last time anything was read, so
      // the reading moves on to the next thing they have not read.
      return firstUnreadOrdinal.clamp(1, total);
    }

    if (!portionComplete) {
      // Read within this period, but the plan is still asking for more: carry
      // on through the portion rather than sitting on what was just read.
      return firstUnreadOrdinal.clamp(1, total);
    }

    // This period's portion is done — hold position so re-opening the app shows
    // what they just read instead of jumping ahead into tomorrow's reading.
    return progress.currentOrdinal.clamp(1, total);
  }
}
