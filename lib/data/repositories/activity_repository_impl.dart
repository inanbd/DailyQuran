import '../../domain/entities/reading_day.dart';
import '../../domain/repositories/activity_repository.dart';
import '../local/activity_dao.dart';

/// Thin pass-through to [ActivityDao], so the domain layer depends on an
/// interface rather than on SQLite.
class ActivityRepositoryImpl implements ActivityRepository {
  ActivityRepositoryImpl(this._dao);

  final ActivityDao _dao;

  @override
  Future<void> addReadingTime(DateTime day, int seconds) =>
      _dao.addReadingTime(day, seconds);

  @override
  Future<bool> markGoalMet(DateTime day, DateTime at) =>
      _dao.markGoalMet(day, at);

  @override
  Future<ReadingDay> dayOf(DateTime day) => _dao.dayOf(day);

  @override
  Future<List<ReadingDay>> daysBetween(DateTime from, DateTime to) =>
      _dao.daysBetween(from, to);

  @override
  Future<List<DateTime>> goalMetDays() => _dao.goalMetDays();
}
