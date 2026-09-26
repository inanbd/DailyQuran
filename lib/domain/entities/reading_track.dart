/// Which of the reader's two readings an action belongs to.
///
/// The app keeps two readings of the Qur'an side by side, each with its own
/// place and its own record of what has been read:
///
///  * [daily] — the Daily Ayah, one ayah a reading period, for as long as it
///    takes. What the app has always been.
///  * [plan] — a planned reading working towards a finish date, with a goal
///    for each day. It exists only while the reader has a plan.
///
/// Keeping them apart is what lets a reader follow a month-long plan without
/// it swallowing their daily ayah, and dip into the daily ayah without it
/// counting towards — or against — their plan.
enum ReadingTrack {
  daily('daily'),
  plan('plan');

  const ReadingTrack(this.storageKey);

  final String storageKey;

  /// The progress scope this track stores its reading under, given the scope
  /// of the edition being read.
  ///
  /// The daily reading keeps the edition's own scope, which is where every
  /// reader's existing progress already lives. The plan gets a sibling scope,
  /// so it shares the same ayat and translations but never the same record.
  String scopeFor(String readingScope) => switch (this) {
        ReadingTrack.daily => readingScope,
        ReadingTrack.plan => '$readingScope#plan',
      };

  static ReadingTrack? fromStorage(String? value) {
    for (final ReadingTrack track in ReadingTrack.values) {
      if (track.storageKey == value) return track;
    }
    return null;
  }
}
