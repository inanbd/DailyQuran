import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/repositories/speech_synthesizer.dart';
import 'providers.dart';

/// The default language a translation is spoken in, used until an edition says
/// otherwise through `QuranEdition.languageCode`.
const String kDefaultSpeechLanguage = 'en-US';

/// One thing being spoken: which ayah, and in which language.
///
/// Only the *translation* is ever spoken. The Arabic of the Qur'an is not read
/// aloud by a synthetic voice — recitation is its own discipline, with rules a
/// text-to-speech engine neither knows nor follows, and an app that offered a
/// button for it would be inviting readers to treat the two as equivalent.
@immutable
class SpokenUtterance {
  const SpokenUtterance({required this.ayahId, required this.languageCode});

  final String ayahId;
  final String languageCode;

  @override
  bool operator ==(Object other) =>
      other is SpokenUtterance &&
      other.ayahId == ayahId &&
      other.languageCode == languageCode;

  @override
  int get hashCode => Object.hash(ayahId, languageCode);

  @override
  String toString() => 'SpokenUtterance($ayahId, $languageCode)';
}

/// Whether this device can speak [languageCode] at all.
///
/// The play button is hidden when it cannot, rather than shown and inert.
final speechAvailableProvider =
    FutureProvider.family<bool, String>((Ref ref, String languageCode) async {
  final SpeechSynthesizer synthesizer = ref.watch(speechSynthesizerProvider);
  return synthesizer.isLanguageAvailable(languageCode);
});

/// What is currently being spoken, or null when silent.
///
/// Held centrally rather than per-widget so that starting one utterance stops
/// another, and so an ayah scrolled out of view cannot leave a stale button.
class SpeechController extends Notifier<SpokenUtterance?> {
  @override
  SpokenUtterance? build() {
    // Captured here rather than read inside the callback: Riverpod forbids
    // touching ref from a life-cycle hook.
    final SpeechSynthesizer synthesizer = ref.watch(speechSynthesizerProvider);
    // The reader navigating away should not leave a voice talking.
    ref.onDispose(synthesizer.stop);
    return null;
  }

  /// Speaks [text] in [languageCode], or stops if that exact utterance is
  /// already speaking.
  Future<void> toggle(
    String ayahId,
    String text, {
    required String languageCode,
  }) async {
    final SpokenUtterance utterance =
        SpokenUtterance(ayahId: ayahId, languageCode: languageCode);
    if (state == utterance) {
      await stop();
      return;
    }

    final SpeechSynthesizer synthesizer = ref.read(speechSynthesizerProvider);
    state = utterance;
    try {
      await synthesizer.speak(text, languageCode: languageCode);
    } on Object {
      // A failed utterance should clear the button, not surface an error over
      // the reading surface.
    } finally {
      // Only clear if this utterance is still the current one: a second tap
      // may have started something else while this was speaking. And only if
      // the controller is still alive — the reader can leave the screen,
      // disposing it, while the engine is mid-sentence.
      if (ref.mounted && state == utterance) state = null;
    }
  }

  Future<void> stop() async {
    state = null;
    await ref.read(speechSynthesizerProvider).stop();
  }
}

final NotifierProvider<SpeechController, SpokenUtterance?>
    speechControllerProvider =
    NotifierProvider<SpeechController, SpokenUtterance?>(SpeechController.new);
