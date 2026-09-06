import 'package:meta/meta.dart';

/// Reading state for one progress scope.
///
/// Every complete edition of the Qur'an shares a scope, so switching
/// translation carries your place with it. The development fixture has its own,
/// so its placeholder progress can never appear as progress through the Qur'an.
@immutable
class ReadingProgress {
  const ReadingProgress({
    required this.scope,
    required this.currentOrdinal,
    required this.totalRead,
    required this.totalAyah,
    this.startedAt,
    this.lastReadAt,
    this.completedAt,
  });

  /// A scope that has never been opened.
  factory ReadingProgress.empty(String scope, int totalAyah) {
    return ReadingProgress(
      scope: scope,
      currentOrdinal: 1,
      totalRead: 0,
      totalAyah: totalAyah,
    );
  }

  final String scope;

  /// Where the reader is right now (1-based). Moves when the reader navigates
  /// and when a new reading period rolls the reading on.
  final int currentOrdinal;

  /// How many ayat in this scope are marked read.
  final int totalRead;

  /// Size of the edition, for percentage and completion checks.
  final int totalAyah;

  final DateTime? startedAt;
  final DateTime? lastReadAt;

  /// Set once every ayah has been read.
  final DateTime? completedAt;

  bool get hasStarted => startedAt != null;
  bool get isComplete => totalAyah > 0 && totalRead >= totalAyah;

  /// 0.0–1.0. Guards against an empty edition.
  double get fraction {
    if (totalAyah <= 0) return 0;
    return (totalRead / totalAyah).clamp(0.0, 1.0);
  }

  /// Percentage rounded to one decimal, e.g. `12.8`.
  double get percentage => double.parse((fraction * 100).toStringAsFixed(1));

  /// Average ayat read per day since starting, or null when there is not yet
  /// enough history to say anything meaningful.
  double? get pacePerDay {
    final DateTime? start = startedAt;
    if (start == null || totalRead < 2) return null;
    final DateTime end = lastReadAt ?? DateTime.now();
    final double days = end.difference(start).inMinutes / (60 * 24);
    if (days < 1) return null;
    return totalRead / days;
  }

  /// Projected finish date. Null unless a pace can be established and there is
  /// something left to read — an estimate is only shown when it means something.
  DateTime? get estimatedCompletion {
    if (isComplete) return null;
    final double? pace = pacePerDay;
    if (pace == null || pace <= 0) return null;
    final int remaining = totalAyah - totalRead;
    final int daysLeft = (remaining / pace).ceil();
    if (daysLeft > 365 * 20) return null;
    return DateTime.now().add(Duration(days: daysLeft));
  }

  ReadingProgress copyWith({
    int? currentOrdinal,
    int? totalRead,
    int? totalAyah,
    DateTime? startedAt,
    DateTime? lastReadAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return ReadingProgress(
      scope: scope,
      currentOrdinal: currentOrdinal ?? this.currentOrdinal,
      totalRead: totalRead ?? this.totalRead,
      totalAyah: totalAyah ?? this.totalAyah,
      startedAt: startedAt ?? this.startedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }
}
