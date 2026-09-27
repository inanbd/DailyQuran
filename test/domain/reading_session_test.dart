import 'package:daily_quran/domain/services/reading_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading time: counted while the reader is evidently reading, and not while
/// the phone sits open on the page with nobody there.
void main() {
  final DateTime nine = DateTime(2026, 1, 7, 9, 0);
  DateTime at(int seconds) => nine.add(Duration(seconds: seconds));

  group('ReadingSession', () {
    test('counts the time between opening the page and leaving it', () {
      final ReadingSession session = ReadingSession()..begin(nine);

      final ReadingStretch? stretch = session.end(at(15));

      expect(stretch, ReadingStretch(nine, at(15)));
      expect(session.isRunning, isFalse);
    });

    test('hands back what has built up as the reader keeps going', () {
      final ReadingSession session = ReadingSession()..begin(nine);

      expect(session.activity(at(10)), isNull);
      // Twenty seconds in: time to save it.
      expect(session.activity(at(20)), ReadingStretch(nine, at(20)));
      // And the next stretch picks up where that one ended.
      expect(session.end(at(30)), ReadingStretch(at(20), at(30)));
    });

    test('stops counting two minutes after the last sign of the reader', () {
      final ReadingSession session = ReadingSession()..begin(nine);
      session.activity(at(10));

      // An hour on the page with nobody touching it.
      final ReadingStretch? stretch = session.end(at(3600));

      expect(stretch, ReadingStretch(nine, at(10 + 120)));
    });

    test('counts what came before stepping away, not the time away', () {
      final ReadingSession session = ReadingSession()..begin(nine);
      session.activity(at(10));

      // Back after ten minutes: only up to when they went quiet counts.
      expect(session.activity(at(610)), ReadingStretch(nine, at(130)));
      // Counting starts again from their return.
      expect(session.end(at(625)), ReadingStretch(at(610), at(625)));
    });

    test('a page opened and left at once records nothing', () {
      final ReadingSession session = ReadingSession()..begin(nine);

      expect(session.end(nine), isNull);
    });

    test('does nothing until it has begun', () {
      final ReadingSession session = ReadingSession();

      expect(session.activity(at(30)), isNull);
      expect(session.end(at(60)), isNull);
    });

    test('beginning twice keeps the first start', () {
      final ReadingSession session = ReadingSession()
        ..begin(nine)
        ..begin(at(10));

      expect(session.end(at(15)), ReadingStretch(nine, at(15)));
    });

    test('a clock set backwards starts afresh rather than counting', () {
      final ReadingSession session = ReadingSession()..begin(nine);

      expect(session.activity(nine.subtract(const Duration(hours: 1))), isNull);
      expect(session.end(nine.subtract(const Duration(minutes: 59))), isNotNull);
    });
  });

  group('ReadingStretch.secondsByDay', () {
    test('keeps a stretch inside one day on that day', () {
      expect(
        ReadingStretch(nine, at(90)).secondsByDay(),
        <DateTime, int>{DateTime(2026, 1, 7): 90},
      );
    });

    test('splits a reading that runs past midnight between the two days', () {
      final ReadingStretch stretch = ReadingStretch(
        DateTime(2026, 1, 7, 23, 59),
        DateTime(2026, 1, 8, 0, 2),
      );

      expect(stretch.secondsByDay(), <DateTime, int>{
        DateTime(2026, 1, 7): 60,
        DateTime(2026, 1, 8): 120,
      });
    });

    test('an empty stretch belongs to no day', () {
      expect(ReadingStretch(nine, nine).secondsByDay(), isEmpty);
    });
  });
}
