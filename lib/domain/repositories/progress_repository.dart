import '../entities/reading_progress.dart';

/// Reading progress, stored per scope.
///
/// A scope is normally the Qur'an itself rather than one translation of it, so
/// changing translation does not restart anyone. Ayat are identified by verse
/// key (`2:255`) for the same reason.
abstract interface class ProgressRepository {
  Future<ReadingProgress> progressFor(String scope, int totalAyah);

  /// Progress for every scope that has been started.
  Future<List<ReadingProgress>> allProgress(Map<String, int> totalsByScope);

  /// Marks a single ayah read. Only this ayah — ayat skipped over are
  /// deliberately left unread.
  Future<ReadingProgress> markRead(
    String scope,
    String verseKey,
    int ordinal,
    int totalAyah, {
    DateTime? at,
  });

  Future<ReadingProgress> markUnread(
    String scope,
    String verseKey,
    int totalAyah,
  );

  /// Moves the reader's position without changing read state.
  Future<ReadingProgress> setCurrentOrdinal(
    String scope,
    int ordinal,
    int totalAyah,
  );

  Future<bool> isRead(String scope, String verseKey);

  /// Read state for a window of ordinals, for list rendering.
  Future<Set<int>> readOrdinalsIn(String scope, int from, int to);

  /// The lowest unread ordinal, or null when everything has been read.
  Future<int?> firstUnreadOrdinal(String scope, int totalAyah);

  /// How many ayat were read at or after [since] — how much of a reading plan's
  /// portion for the current period is done.
  Future<int> readCountSince(String scope, DateTime since);

  /// Clears all read state for a scope so it can be read again, milestones
  /// included — a reading begun again passes each of them afresh.
  Future<ReadingProgress> resetScope(String scope, int totalAyah);

  /// Records that [percent]% of [scope] has been read.
  ///
  /// Returns true only the first time, so a milestone is congratulated once
  /// however often the reading dips under it and climbs back — an ayah marked
  /// unread and read again is not a new achievement.
  Future<bool> reachMilestone(String scope, int percent, DateTime at);

  /// Copies [from]'s read state and position into [to], keeping anything [to]
  /// already has.
  Future<void> copyScope(String from, String to);
}
