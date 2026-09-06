import 'dart:async';
import 'dart:convert';

import 'package:daily_quran/domain/entities/ayah.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/entities/notification_preferences.dart';
import 'package:daily_quran/domain/entities/quran_edition.dart';
import 'package:daily_quran/domain/entities/surah.dart';
import 'package:daily_quran/domain/repositories/notification_scheduler.dart';
import 'package:daily_quran/domain/repositories/quran_content_source.dart';
import 'package:daily_quran/domain/repositories/speech_synthesizer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An in-memory content source, so tests never depend on bundled assets.
class FakeContentSource implements QuranContentSource {
  FakeContentSource({
    required this.editions,
    required this.ayatByEdition,
    this.surahsByEdition = const <String, List<Surah>>{},
  });

  /// A single edition of [count] ayat, laid out over surahs of [surahLength].
  factory FakeContentSource.single({
    String id = 'test_edition',
    String title = 'Test Edition',
    int count = 10,
    int surahLength = 5,
    String progressScope = 'quran',
    String languageCode = 'en-US',
    bool isRightToLeft = false,
    ContentVerification verification = ContentVerification.verified,
    String Function(int ordinal)? translationText,
  }) {
    final QuranEdition edition = QuranEdition(
      id: id,
      slug: id,
      titleEnglish: title,
      titleArabic: 'القرآن الكريم',
      translator: 'Test translator',
      description: 'An edition used by the test suite.',
      languageName: 'English',
      languageCode: languageCode,
      isRightToLeft: isRightToLeft,
      totalAyah: count,
      progressScope: progressScope,
      source: const ContentSource(name: 'Test fixture'),
      verification: verification,
    );

    final List<Ayah> ayat = <Ayah>[];
    final Map<int, int> countsBySurah = <int, int>{};
    for (int ordinal = 1; ordinal <= count; ordinal++) {
      final int surah = ((ordinal - 1) ~/ surahLength) + 1;
      final int ayah = ((ordinal - 1) % surahLength) + 1;
      countsBySurah[surah] = (countsBySurah[surah] ?? 0) + 1;
      ayat.add(
        Ayah(
          id: '$id:$surah:$ayah',
          editionId: id,
          ordinal: ordinal,
          surahNumber: surah,
          ayahNumber: ayah,
          surahNameArabic: 'سورة $surah',
          surahNameEnglish: 'Surah $surah',
          arabicText: 'نص عربي رقم $ordinal',
          translationText:
              translationText?.call(ordinal) ?? 'Translation number $ordinal.',
          transliteration: 'Nass raqm $ordinal',
          juz: 30,
          reference: 'Surah $surah $surah:$ayah',
        ),
      );
    }

    return FakeContentSource(
      editions: <QuranEdition>[edition],
      ayatByEdition: <String, List<Ayah>>{id: ayat},
      surahsByEdition: <String, List<Surah>>{
        id: <Surah>[
          for (final MapEntry<int, int> entry in countsBySurah.entries)
            Surah(
              editionId: id,
              number: entry.key,
              nameArabic: 'سورة ${entry.key}',
              nameTransliterated: 'Surah ${entry.key}',
              nameEnglish: 'Test surah ${entry.key}',
              ayahCount: entry.value,
              revelationPlace: RevelationPlace.meccan,
            ),
        ],
      },
    );
  }

  final List<QuranEdition> editions;
  final Map<String, List<Ayah>> ayatByEdition;
  final Map<String, List<Surah>> surahsByEdition;

  int loadAyatCalls = 0;

  @override
  Future<List<QuranEdition>> loadCatalog() async => editions;

  @override
  Future<bool> hasContentFor(String editionId) async =>
      ayatByEdition.containsKey(editionId);

  @override
  Future<List<Ayah>> loadAyat(String editionId) async {
    loadAyatCalls++;
    final List<Ayah>? ayat = ayatByEdition[editionId];
    if (ayat == null) throw StateError('no content for $editionId');
    return ayat;
  }

  @override
  Future<List<Surah>> loadSurahs(String editionId) async =>
      surahsByEdition[editionId] ?? const <Surah>[];
}

/// Records what the app asked the platform to schedule, without touching a
/// real notification plugin.
class FakeNotificationScheduler implements NotificationScheduler {
  FakeNotificationScheduler({
    this.status = NotificationPermissionStatus.granted,
    this.otherRequirements = allSatisfied,
    this.grantsOnRequest = true,
    this.launchDeepLink,
  });

  /// A platform with nothing to ask for beyond notification permission, which
  /// is all most tests care about.
  static const ReminderReadiness allSatisfied = ReminderReadiness(
    notifications: NotificationPermissionStatus.granted,
    exactTiming: NotificationPermissionStatus.unsupported,
    background: NotificationPermissionStatus.unsupported,
  );

  /// An Android-shaped platform where punctuality still has to be asked for.
  static const ReminderReadiness androidUnasked = ReminderReadiness(
    notifications: NotificationPermissionStatus.granted,
    exactTiming: NotificationPermissionStatus.denied,
    background: NotificationPermissionStatus.denied,
  );

  /// Notification permission, as the shorthand most tests care about.
  NotificationPermissionStatus status;

  /// Whether a prompt is answered yes. False stands in for a reader who
  /// declines, or an OS that has stopped showing the prompt at all.
  bool grantsOnRequest;

  QuranDeepLink? launchDeepLink;

  /// Everything except notification permission, which [status] owns.
  ReminderReadiness otherRequirements;

  final List<NotificationPreferences> scheduledPreferences =
      <NotificationPreferences>[];
  final List<String?> scheduledEditionIds = <String?>[];
  final List<ReminderRequirement> requested = <ReminderRequirement>[];
  int cancelAllCalls = 0;
  int settingsOpened = 0;
  bool initialized = false;

  /// How many times the OS notification prompt was raised.
  int get permissionRequests => requested
      .where((ReminderRequirement it) => it == ReminderRequirement.notifications)
      .length;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<ReminderReadiness> readiness() async =>
      otherRequirements.copyWith(notifications: status);

  @override
  Future<bool> request(ReminderRequirement requirement) async {
    requested.add(requirement);
    if (!grantsOnRequest) return false;
    switch (requirement) {
      case ReminderRequirement.notifications:
        status = NotificationPermissionStatus.granted;
      case ReminderRequirement.exactTiming:
        otherRequirements = otherRequirements
            .copyWith(exactTiming: NotificationPermissionStatus.granted);
      case ReminderRequirement.background:
        otherRequirements = otherRequirements
            .copyWith(background: NotificationPermissionStatus.granted);
    }
    return true;
  }

  @override
  Future<bool> openSystemNotificationSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<void> reschedule({
    required NotificationPreferences preferences,
    required String? editionId,
  }) async {
    scheduledPreferences.add(preferences);
    scheduledEditionIds.add(editionId);
  }

  @override
  Future<void> cancelAll() async => cancelAllCalls++;

  @override
  Future<QuranDeepLink?> consumeLaunchDeepLink() async {
    final QuranDeepLink? link = launchDeepLink;
    launchDeepLink = null;
    return link;
  }

  @override
  Stream<QuranDeepLink> get deepLinks => const Stream<QuranDeepLink>.empty();

  @override
  Future<int> pendingCount() async => scheduledPreferences.length;
}

/// An [AssetBundle] backed by a map, for exercising the real asset parser.
class MapAssetBundle extends CachingAssetBundle {
  MapAssetBundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<ByteData> load(String key) async {
    final String? value = assets[key];
    if (value == null) {
      throw FlutterError('Asset not found: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }
}

/// A [SpeechSynthesizer] that records what it was asked to say.
///
/// Speaking completes immediately, so a test never has to wait on a real
/// engine; [completeManually] holds the utterance open when a test needs to
/// observe the speaking state.
class FakeSpeechSynthesizer implements SpeechSynthesizer {
  FakeSpeechSynthesizer({
    this.available = true,
    this.unavailableLanguages = const <String>{},
    this.completeManually = false,
  });

  /// Whether the device claims any voice at all.
  bool available;

  /// Languages this device specifically lacks, for the common real case of an
  /// English voice installed and another not.
  Set<String> unavailableLanguages;

  /// When true, [speak] does not complete until [finish] is called.
  bool completeManually;

  final List<String> spoken = <String>[];
  final List<String> languages = <String>[];
  int stopCalls = 0;
  int disposeCalls = 0;

  Completer<void>? _pending;

  @override
  Future<bool> isLanguageAvailable(String languageCode) async =>
      available && !unavailableLanguages.contains(languageCode);

  @override
  Future<void> speak(String text, {required String languageCode}) async {
    spoken.add(text);
    languages.add(languageCode);
    if (!completeManually) return;
    final Completer<void> completer = Completer<void>();
    _pending = completer;
    return completer.future;
  }

  /// Completes an utterance held open by [completeManually].
  void finish() {
    _pending?.complete();
    _pending = null;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _pending?.complete();
    _pending = null;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}
