import '../../domain/entities/reading_progress.dart';
import '../../domain/repositories/progress_repository.dart';
import '../local/progress_dao.dart';

/// Thin pass-through to [ProgressDao]. Kept as its own type so the domain layer
/// depends on an interface rather than on SQLite.
class ProgressRepositoryImpl implements ProgressRepository {
  ProgressRepositoryImpl(this._dao);

  final ProgressDao _dao;

  @override
  Future<ReadingProgress> progressFor(String scope, int totalAyah) =>
      _dao.progressFor(scope, totalAyah);

  @override
  Future<List<ReadingProgress>> allProgress(Map<String, int> totals) =>
      _dao.allProgress(totals);

  @override
  Future<ReadingProgress> markRead(
    String scope,
    String verseKey,
    int ordinal,
    int totalAyah, {
    DateTime? at,
  }) =>
      _dao.markRead(scope, verseKey, ordinal, totalAyah, at: at);

  @override
  Future<ReadingProgress> markUnread(
    String scope,
    String verseKey,
    int totalAyah,
  ) =>
      _dao.markUnread(scope, verseKey, totalAyah);

  @override
  Future<ReadingProgress> setCurrentOrdinal(
    String scope,
    int ordinal,
    int totalAyah,
  ) =>
      _dao.setCurrentOrdinal(scope, ordinal, totalAyah);

  @override
  Future<bool> isRead(String scope, String verseKey) =>
      _dao.isRead(scope, verseKey);

  @override
  Future<Set<int>> readOrdinalsIn(String scope, int from, int to) =>
      _dao.readOrdinalsIn(scope, from, to);

  @override
  Future<int?> firstUnreadOrdinal(String scope, int totalAyah) =>
      _dao.firstUnreadOrdinal(scope, totalAyah);

  @override
  Future<int> readCountSince(String scope, DateTime since) =>
      _dao.readCountSince(scope, since);

  @override
  Future<ReadingProgress> resetScope(String scope, int totalAyah) =>
      _dao.resetScope(scope, totalAyah);

  @override
  Future<void> copyScope(String from, String to) => _dao.copyScope(from, to);
}
