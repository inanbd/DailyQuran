import 'package:daily_quran/domain/entities/ayah.dart';
import 'package:daily_quran/domain/entities/enums.dart';
import 'package:daily_quran/domain/entities/reminder_message.dart';
import 'package:daily_quran/domain/services/reminder_message_composer.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a reminder is allowed to say.
///
/// The default reveals nothing, each step up reveals exactly one more thing,
/// and a setting that cannot be honoured steps back down rather than arming an
/// empty notification.
void main() {
  const String arabic = 'ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ';
  const String english = 'Allah — there is no deity except Him.';

  Ayah ayah({String? translationText = english, String? arabicText = arabic}) {
    return Ayah(
      id: 'test:2:255',
      editionId: 'test',
      ordinal: 262,
      surahNumber: 2,
      ayahNumber: 255,
      surahNameEnglish: 'Al-Baqarah',
      arabicText: arabicText,
      translationText: translationText,
    );
  }

  ReminderMessage compose(
    ReminderContent content, {
    int ayatToRead = 1,
    Ayah? verse,
  }) {
    return ReminderMessageComposer.compose(
      content: content,
      ayatToRead: ayatToRead,
      ayah: verse,
    );
  }

  group('revealing nothing', () {
    test('is the plain invitation on the default plan', () {
      expect(
        compose(ReminderContent.invitation, verse: ayah()),
        ReminderMessage.invitation,
      );
    });

    test('counts the portion out when a plan asks for more than one', () {
      final ReminderMessage message =
          compose(ReminderContent.invitation, ayatToRead: 18, verse: ayah());

      expect(message.body, 'Your 18 ayat are ready.');
    });

    test('carries no Qur’an text even when an ayah is available', () {
      final ReminderMessage message =
          compose(ReminderContent.invitation, ayatToRead: 18, verse: ayah());

      expect(message.body, isNot(contains(arabic)));
      expect(message.body, isNot(contains(english)));
      expect(message.body, isNot(contains('Al-Baqarah')));
    });
  });

  group('revealing the reference', () {
    test('names the ayah and the size of the portion', () {
      final ReminderMessage message =
          compose(ReminderContent.reference, ayatToRead: 18, verse: ayah());

      expect(message.body, 'Al-Baqarah 2:255 · 18 ayat');
    });

    test('drops the count on a one-ayah plan, where it says nothing', () {
      final ReminderMessage message =
          compose(ReminderContent.reference, verse: ayah());

      expect(message.body, 'Al-Baqarah 2:255');
    });

    test('is a citation, not scripture', () {
      final ReminderMessage message =
          compose(ReminderContent.reference, verse: ayah());

      expect(message.body, isNot(contains(arabic)));
      expect(message.body, isNot(contains(english)));
    });
  });

  group('revealing the text', () {
    test('puts the translation in the body and the citation in the title', () {
      final ReminderMessage message =
          compose(ReminderContent.translation, ayatToRead: 18, verse: ayah());

      expect(message.title, 'Al-Baqarah 2:255 · 18 ayat');
      expect(message.body, english);
    });

    test('does the same for the Arabic', () {
      final ReminderMessage message =
          compose(ReminderContent.arabic, verse: ayah());

      expect(message.title, 'Al-Baqarah 2:255');
      expect(message.body, arabic);
    });
  });

  group('falling back rather than failing', () {
    test('an edition with no translation shows the reference instead', () {
      final ReminderMessage message = compose(
        ReminderContent.translation,
        verse: ayah(translationText: null),
      );

      expect(message.body, 'Al-Baqarah 2:255');
    });

    test('an empty text is treated as no text at all', () {
      final ReminderMessage message = compose(
        ReminderContent.arabic,
        verse: ayah(arabicText: '   '),
      );

      expect(message.body, 'Al-Baqarah 2:255');
    });

    test('no ayah at all falls all the way back to the invitation', () {
      for (final ReminderContent content in ReminderContent.values) {
        expect(
          compose(content),
          ReminderMessage.invitation,
          reason: '${content.storageKey} with no ayah should still arm',
        );
      }
    });

    test('a reminder is never armed with an empty body', () {
      for (final ReminderContent content in ReminderContent.values) {
        for (final Ayah? verse in <Ayah?>[
          null,
          ayah(),
          ayah(translationText: null),
          ayah(arabicText: null, translationText: null),
        ]) {
          final ReminderMessage message =
              compose(content, ayatToRead: 18, verse: verse);
          expect(message.title.trim(), isNotEmpty);
          expect(message.body.trim(), isNotEmpty);
        }
      }
    });
  });
}
