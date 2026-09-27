import 'package:meta/meta.dart';

/// A stretch of time spent reading.
@immutable
class ReadingStretch {
  const ReadingStretch(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool get isEmpty => !end.isAfter(start);

  Duration get duration => isEmpty ? Duration.zero : end.difference(start);

  /// Whole seconds read on each calendar day the stretch touches.
  ///
  /// A reading that runs past midnight counts towards both days, each for
  /// the part of it that fell on that day — which is what "time read today"
  /// has to mean for a goal that starts again every morning.
  Map<DateTime, int> secondsByDay() {
    final Map<DateTime, int> result = <DateTime, int>{};
    if (isEmpty) return result;
    DateTime cursor = start;
    while (cursor.isBefore(end)) {
      final DateTime day = DateTime(cursor.year, cursor.month, cursor.day);
      final DateTime nextDay = DateTime(day.year, day.month, day.day + 1);
      final DateTime until = nextDay.isBefore(end) ? nextDay : end;
      final int seconds = until.difference(cursor).inSeconds;
      if (seconds > 0) result[day] = (result[day] ?? 0) + seconds;
      cursor = until;
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is ReadingStretch && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'ReadingStretch($start – $end)';
}

/// Measures time spent reading, from the moments the reader shows they are.
///
/// The clock runs while the reading is on screen, but only for so long after
/// the last sign of the reader — a touch, a scroll, a turned page. A phone
/// left open on the Today screen overnight is not eight hours of reading:
/// after [idleAfter] with no sign, the time stops counting at the last moment
/// it was fair to assume they were reading, and starts again at the next sign.
///
/// Pure bookkeeping, fed the time by its caller. It never saves anything
/// itself; it hands back stretches for the caller to save.
class ReadingSession {
  ReadingSession({
    this.idleAfter = defaultIdleAfter,
    this.saveEvery = defaultSaveEvery,
  });

  /// Long enough to read a long ayah and sit with it without touching the
  /// screen; short enough that walking away does not count as reading.
  static const Duration defaultIdleAfter = Duration(minutes: 2);

  /// How much reading builds up before it is handed back to be saved, so a
  /// long sitting is kept safe and a goal can be seen to fill as it is read.
  static const Duration defaultSaveEvery = Duration(seconds: 20);

  final Duration idleAfter;
  final Duration saveEvery;

  /// Start of the reading not yet handed back, or null while not running.
  DateTime? _start;

  /// The latest sign of the reader.
  DateTime? _lastSign;

  bool get isRunning => _start != null;

  /// Starts measuring: the reading has come on screen. Does nothing if it is
  /// already running.
  void begin(DateTime now) {
    if (isRunning) return;
    _start = now;
    _lastSign = now;
  }

  /// A sign the reader is reading.
  ///
  /// Returns a stretch to save when there is one: either the reader had gone
  /// quiet and has come back — the time up to when they went quiet — or
  /// enough has built up since the last save.
  ReadingStretch? activity(DateTime now) {
    final DateTime? start = _start;
    final DateTime? lastSign = _lastSign;
    if (start == null || lastSign == null) return null;

    // A clock set backwards: nothing sensible can be measured across it.
    if (now.isBefore(start)) {
      _start = now;
      _lastSign = now;
      return null;
    }

    final DateTime quietFrom = lastSign.add(idleAfter);
    if (now.isAfter(quietFrom)) {
      // They stepped away. What they read before they did counts; the time
      // away does not.
      _start = now;
      _lastSign = now;
      return _nonEmpty(ReadingStretch(start, quietFrom));
    }

    _lastSign = now;
    if (now.difference(start) >= saveEvery) {
      _start = now;
      return _nonEmpty(ReadingStretch(start, now));
    }
    return null;
  }

  /// Stops measuring — the reading has gone off screen — and returns what
  /// has not yet been saved.
  ReadingStretch? end(DateTime now) {
    final DateTime? start = _start;
    final DateTime? lastSign = _lastSign;
    _start = null;
    _lastSign = null;
    if (start == null || lastSign == null) return null;
    final DateTime quietFrom = lastSign.add(idleAfter);
    return _nonEmpty(
      ReadingStretch(start, now.isAfter(quietFrom) ? quietFrom : now),
    );
  }

  static ReadingStretch? _nonEmpty(ReadingStretch stretch) =>
      stretch.duration.inSeconds < 1 ? null : stretch;
}
