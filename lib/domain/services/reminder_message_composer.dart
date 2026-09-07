import '../entities/ayah.dart';
import '../entities/enums.dart';
import '../entities/reminder_message.dart';

/// Builds the text of a reminder from what the reader asked it to reveal.
///
/// ## Why this is a choice at all
///
/// A reminder lands on a lock screen, where whoever is nearby can read it. That
/// makes "what does it say" a decision only the reader can make: one person
/// wants the ayah waiting for them, another wants nothing on a screen a
/// stranger might glance at. So the app asks, and defaults to revealing
/// nothing.
///
/// ## Falling back rather than failing
///
/// Each setting needs more than the last: a reference needs an ayah, and the
/// text settings need that ayah to actually carry the text. When it does not —
/// an edition with no transliteration, a reminder armed before an edition was
/// chosen — the composer steps *down* the disclosure ladder rather than arming
/// an empty notification. A reader can therefore never be shown less than they
/// asked for by accident, and never shown a blank reminder at all.
abstract final class ReminderMessageComposer {
  static ReminderMessage compose({
    required ReminderContent content,
    required int ayatToRead,
    Ayah? ayah,
  }) {
    switch (content) {
      case ReminderContent.invitation:
        return _invitation(ayatToRead);

      case ReminderContent.reference:
        final String? reference = _reference(ayah);
        if (reference == null) return _invitation(ayatToRead);
        return ReminderMessage(
          title: ReminderMessage.invitation.title,
          body: _withCount(reference, ayatToRead),
        );

      case ReminderContent.translation:
        return _text(ayah?.translationText, ayah, ayatToRead);

      case ReminderContent.arabic:
        return _text(ayah?.arabicText, ayah, ayatToRead);
    }
  }

  /// A reminder that reveals nothing but how much there is to read.
  static ReminderMessage _invitation(int ayatToRead) {
    if (ayatToRead <= 1) return ReminderMessage.invitation;
    return ReminderMessage(
      title: ReminderMessage.invitation.title,
      body: 'Your $ayatToRead ayat are ready.',
    );
  }

  /// Qur'an text in the body, with the citation promoted to the title so the
  /// reader can see what they are being shown before they read it.
  static ReminderMessage _text(String? text, Ayah? ayah, int ayatToRead) {
    final String? reference = _reference(ayah);
    final String? trimmed = text?.trim();
    if (reference == null || trimmed == null || trimmed.isEmpty) {
      // Nothing to show at this level: fall back to whatever the next one down
      // can manage.
      return compose(
        content: ReminderContent.reference,
        ayatToRead: ayatToRead,
        ayah: ayah,
      );
    }
    return ReminderMessage(
      title: _withCount(reference, ayatToRead),
      body: trimmed,
    );
  }

  /// "Al-Baqarah 2:255", or just "2:255" where the surah has no English name.
  static String? _reference(Ayah? ayah) {
    if (ayah == null) return null;
    final String key = ayah.verseKey.trim();
    if (key.isEmpty) return null;
    final String? surah = ayah.surahNameEnglish?.trim();
    if (surah == null || surah.isEmpty) return key;
    return '$surah $key';
  }

  /// Appends the size of the portion, but only when there is more than one ayah
  /// in it — "· 1 ayah" is noise on the default plan.
  static String _withCount(String reference, int ayatToRead) {
    if (ayatToRead <= 1) return reference;
    return '$reference · $ayatToRead ayat';
  }
}
