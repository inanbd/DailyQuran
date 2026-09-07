import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/content/asset_quran_content_source.dart';
import '../data/local/app_database.dart';
import '../data/local/ayah_dao.dart';
import '../data/local/favourites_dao.dart';
import '../data/local/preferences_store.dart';
import '../data/local/progress_dao.dart';
import '../data/notifications/local_notification_scheduler.dart';
import '../data/repositories/favourites_repository_impl.dart';
import '../data/repositories/progress_repository_impl.dart';
import '../data/repositories/quran_repository_impl.dart';
import '../data/speech/flutter_tts_speech_synthesizer.dart';
import '../domain/entities/ayah.dart';
import '../domain/entities/enums.dart';
import '../domain/entities/notification_preferences.dart';
import '../domain/entities/quran_edition.dart';
import '../domain/entities/reading_progress.dart';
import '../domain/entities/user_preferences.dart';
import '../domain/repositories/favourites_repository.dart';
import '../domain/repositories/notification_scheduler.dart';
import '../domain/repositories/preferences_repository.dart';
import '../domain/repositories/progress_repository.dart';
import '../domain/repositories/quran_content_source.dart';
import '../domain/repositories/quran_repository.dart';
import '../domain/repositories/speech_synthesizer.dart';
import '../domain/services/plan_scheduler.dart';
import '../domain/services/reminder_message_composer.dart';
import '../domain/services/reminder_schedule.dart';

/// Thrown if a provider that must be overridden at startup is read directly.
Never _mustOverride(String name) =>
    throw StateError('$name must be overridden in ProviderScope.');

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------

/// The clock, as a seam.
///
/// Everything that asks "has a new reading period begun?" goes through here, so
/// tests can advance days without waiting for them.
final Provider<DateTime Function()> clockProvider =
    Provider<DateTime Function()>((Ref ref) => DateTime.now);

/// Overridden in `main()` once shared preferences have loaded.
final Provider<SharedPreferences> sharedPreferencesProvider =
    Provider<SharedPreferences>(
  (Ref ref) => _mustOverride('sharedPreferencesProvider'),
);

final Provider<AppDatabase> appDatabaseProvider =
    Provider<AppDatabase>((Ref ref) {
  final AppDatabase database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

/// The single seam for Qur'an content. Override this to read from an API, a
/// downloaded pack, or a publisher's SDK instead of bundled assets — nothing
/// above this line changes.
final Provider<QuranContentSource> quranContentSourceProvider =
    Provider<QuranContentSource>((Ref ref) => AssetQuranContentSource());

final Provider<AyahDao> ayahDaoProvider =
    Provider<AyahDao>((Ref ref) => AyahDao(ref.watch(appDatabaseProvider)));

final Provider<ProgressDao> progressDaoProvider = Provider<ProgressDao>(
  (Ref ref) => ProgressDao(ref.watch(appDatabaseProvider)),
);

final Provider<FavouritesDao> favouritesDaoProvider = Provider<FavouritesDao>(
  (Ref ref) => FavouritesDao(ref.watch(appDatabaseProvider)),
);

final Provider<QuranRepository> quranRepositoryProvider =
    Provider<QuranRepository>(
  (Ref ref) => QuranRepositoryImpl(
    contentSource: ref.watch(quranContentSourceProvider),
    dao: ref.watch(ayahDaoProvider),
  ),
);

final Provider<ProgressRepository> progressRepositoryProvider =
    Provider<ProgressRepository>(
  (Ref ref) => ProgressRepositoryImpl(ref.watch(progressDaoProvider)),
);

final Provider<FavouritesRepository> favouritesRepositoryProvider =
    Provider<FavouritesRepository>(
  (Ref ref) => FavouritesRepositoryImpl(
    favouritesDao: ref.watch(favouritesDaoProvider),
    ayahDao: ref.watch(ayahDaoProvider),
  ),
);

final Provider<PreferencesRepository> preferencesRepositoryProvider =
    Provider<PreferencesRepository>(
  (Ref ref) => PreferencesStore(ref.watch(sharedPreferencesProvider)),
);

final Provider<NotificationScheduler> notificationSchedulerProvider =
    Provider<NotificationScheduler>((Ref ref) => LocalNotificationScheduler());

/// Text-to-speech for the translation. Disposed with the scope so the engine
/// is released when the app shuts down.
final Provider<SpeechSynthesizer> speechSynthesizerProvider =
    Provider<SpeechSynthesizer>((Ref ref) {
  final SpeechSynthesizer synthesizer = FlutterTtsSpeechSynthesizer();
  ref.onDispose(synthesizer.dispose);
  return synthesizer;
});

// ---------------------------------------------------------------------------
// Preferences
// ---------------------------------------------------------------------------

/// Preferences read once before the first frame, so the UI never has to render
/// a loading state for something as basic as the theme.
final Provider<UserPreferences> initialUserPreferencesProvider =
    Provider<UserPreferences>(
  (Ref ref) => _mustOverride('initialUserPreferencesProvider'),
);

final Provider<NotificationPreferences> initialNotificationPreferencesProvider =
    Provider<NotificationPreferences>(
  (Ref ref) => _mustOverride('initialNotificationPreferencesProvider'),
);

class UserPreferencesController extends Notifier<UserPreferences> {
  @override
  UserPreferences build() => ref.watch(initialUserPreferencesProvider);

  Future<void> update(UserPreferences next) async {
    state = next;
    await ref.read(preferencesRepositoryProvider).saveUserPreferences(next);
  }

  /// Opens [editionId] as the translation being read.
  ///
  /// Choosing the one already showing underneath promotes it rather than
  /// leaving the same translation stacked on itself: the reader plainly meant
  /// to read it, and two identical columns would be nothing but a bug.
  Future<void> setCurrentEdition(String editionId) {
    return update(
      state.copyWith(
        currentEditionId: editionId,
        clearSecondaryEdition: state.secondaryEditionId == editionId,
      ),
    );
  }

  /// Shows [editionId] beneath the current translation, or clears the second
  /// translation when given null.
  ///
  /// Asking for the translation already on top is treated as asking for one
  /// translation, for the same reason as above.
  Future<void> setSecondaryEdition(String? editionId) {
    if (editionId == null || editionId == state.currentEditionId) {
      return update(state.copyWith(clearSecondaryEdition: true));
    }
    return update(state.copyWith(secondaryEditionId: editionId));
  }

  Future<void> completeOnboarding() =>
      update(state.copyWith(onboardingComplete: true));
}

final NotifierProvider<UserPreferencesController, UserPreferences>
    userPreferencesProvider =
    NotifierProvider<UserPreferencesController, UserPreferences>(
  UserPreferencesController.new,
);

class NotificationPreferencesController
    extends Notifier<NotificationPreferences> {
  @override
  NotificationPreferences build() =>
      ref.watch(initialNotificationPreferencesProvider);

  /// Persists [next] and re-arms the OS reminders to match.
  ///
  /// Rescheduling always goes through here, so a frequency, time or edition
  /// change can never leave a stale reminder behind.
  Future<void> update(NotificationPreferences next) async {
    state = next;
    await ref
        .read(preferencesRepositoryProvider)
        .saveNotificationPreferences(next);
    await applyToScheduler();
  }

  /// Re-arms the OS reminders from the current preferences and current edition.
  ///
  /// Never throws. Reminders are an accessory to reading, and the platform can
  /// refuse to arm one for reasons outside the app's control — a permission
  /// withdrawn mid-call, an OEM alarm quota. A settings screen that threw on
  /// the way out would be a worse outcome than a reminder that did not arm.
  Future<void> applyToScheduler() async {
    try {
      final NotificationScheduler scheduler =
          ref.read(notificationSchedulerProvider);
      await scheduler.reschedule(
        preferences: state,
        editionId: ref.read(userPreferencesProvider).currentEditionId,
        message: await _composeMessage(),
      );
    } on Object catch (error, stack) {
      debugPrint('Daily Quran: could not arm reminders: $error\n$stack');
    }
    ref.invalidate(reminderReadinessProvider);
  }

  /// The text the next reminder should carry.
  ///
  /// Reads repositories directly rather than the Today controller, which would
  /// be a cycle — the Today screen watches these preferences to know where its
  /// reading period starts.
  ///
  /// Any failure falls back to the plain invitation. A reminder that reveals
  /// less than the reader asked for is a small disappointment; one that fails
  /// to arm at all is a broken feature.
  Future<ReminderMessage> _composeMessage() async {
    // Nothing will be armed, so there is nothing to say. Worth checking first:
    // rescheduling with reminders off still runs on every launch, to clear
    // anything the OS is holding.
    if (!state.enabled) return ReminderMessage.invitation;

    final UserPreferences preferences = ref.read(userPreferencesProvider);

    // The default install — one ayah a period, revealing nothing — has a fixed
    // answer, so nothing is added to startup for a reader who changed neither
    // setting.
    if (state.content == ReminderContent.invitation &&
        !preferences.plan.isPaced) {
      return ReminderMessage.invitation;
    }

    final String? editionId = preferences.currentEditionId;
    if (editionId == null) return ReminderMessage.invitation;

    try {
      final QuranRepository quran = ref.read(quranRepositoryProvider);
      final QuranEdition? edition = await quran.edition(editionId);
      if (edition == null || edition.totalAyah <= 0) {
        return ReminderMessage.invitation;
      }

      final ProgressRepository progressRepository =
          ref.read(progressRepositoryProvider);
      final ReadingProgress progress = await progressRepository.progressFor(
        edition.scope,
        edition.totalAyah,
      );

      // Sized for the period the reminder will *land* in, not the one being
      // left: on a catch-up plan those are different numbers, and the reader
      // should be told the one they are about to be asked for.
      final DateTime now = ref.read(clockProvider)();
      final DateTime arrivesAt =
          ReminderSchedule(state).nextOccurrenceAfter(now) ?? now;
      final ReadingPortion portion = PlanScheduler.resolve(
        plan: preferences.plan,
        progress: progress,
        notificationPreferences: state,
        readThisPeriod: 0,
        now: arrivesAt,
      );

      // The ayah named is the one the reader will actually land on — the first
      // they have not read, never wherever they last browsed to.
      Ayah? ayah;
      if (state.content != ReminderContent.invitation) {
        final int? ordinal = await progressRepository.firstUnreadOrdinal(
          edition.scope,
          edition.totalAyah,
        );
        if (ordinal != null) ayah = await quran.ayahAt(editionId, ordinal);
      }

      return ReminderMessageComposer.compose(
        content: state.content,
        ayatToRead: portion.target,
        ayah: ayah,
      );
    } on Object catch (error) {
      debugPrint('Daily Quran: falling back to a plain reminder ($error)');
      return ReminderMessage.invitation;
    }
  }
}

final NotifierProvider<NotificationPreferencesController,
        NotificationPreferences> notificationPreferencesProvider =
    NotifierProvider<NotificationPreferencesController, NotificationPreferences>(
  NotificationPreferencesController.new,
);

/// What the operating system currently allows reminders to do — arrive at
/// all, arrive on the minute, survive the phone putting the app to sleep.
///
/// Re-read whenever the app resumes, because the reader may have changed any
/// of it in system settings while the app was in the background.
final FutureProvider<ReminderReadiness> reminderReadinessProvider =
    FutureProvider<ReminderReadiness>(
  (Ref ref) => ref.watch(notificationSchedulerProvider).readiness(),
);
