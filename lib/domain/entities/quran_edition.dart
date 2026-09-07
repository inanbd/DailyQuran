import 'package:meta/meta.dart';

import 'enums.dart';

/// An edition of the Qur'an available to read: the Arabic text paired with one
/// translation.
///
/// Everything here is bibliographic metadata about the edition plus provenance
/// for its text. It never contains Qur'an text itself.
/// Unicode U+2068 FIRST STRONG ISOLATE: opens a run whose direction is taken
/// from its own first strong character rather than the text around it.
const int _firstStrongIsolate = 0x2068;

/// Unicode U+2069 POP DIRECTIONAL ISOLATE: closes the run above.
const int _popDirectionalIsolate = 0x2069;

@immutable
class QuranEdition {
  const QuranEdition({
    required this.id,
    required this.slug,
    required this.titleEnglish,
    required this.titleArabic,
    required this.translator,
    required this.description,
    required this.totalAyah,
    required this.source,
    required this.verification,
    this.languageName = 'English',
    this.languageNativeName,
    this.languageCode = 'en-US',
    this.isRightToLeft = false,
    this.translatorArabic,
    this.progressScope,
    this.isInstalled = false,
    this.isAvailable = false,
  });

  /// Stable identifier used as a foreign key by preferences.
  final String id;

  /// URL/asset-friendly identifier.
  final String slug;

  /// Name of the translation, e.g. `Saheeh International`.
  final String titleEnglish;

  /// Native title, normally `القرآن الكريم`. Empty when unknown.
  final String titleArabic;

  /// Who produced the translation.
  final String translator;
  final String? translatorArabic;

  final String description;

  /// Human-readable language of the translation, e.g. `English`.
  final String languageName;

  /// The language's own name for itself, e.g. `اردو` for Urdu. Null where the
  /// catalog gives none, and always null where it would only repeat
  /// [languageName].
  final String? languageNativeName;

  /// The language as it is shown to the reader: its English name, followed by
  /// its own name where the two differ, e.g. `Urdu (اردو)`.
  ///
  /// Both are kept. The English name is what a reader scanning the list is
  /// most likely to be searching for; the native name is how a speaker of that
  /// language recognises it at a glance.
  ///
  /// The native name is wrapped in a Unicode isolate so a right-to-left one —
  /// اردو, العربية — cannot reorder the brackets around it. Without it the
  /// closing bracket is a direction-neutral character next to RTL text and
  /// bidi resolution drags it to the wrong side, giving `Urdu )اردو(`.
  String get languageLabel {
    final String? native = languageNativeName;
    if (native == null || native.isEmpty || native == languageName) {
      return languageName;
    }
    final String isolated = String.fromCharCode(_firstStrongIsolate) +
        native +
        String.fromCharCode(_popDirectionalIsolate);
    return '$languageName ($isolated)';
  }

  /// BCP-47 tag for the translation, used to pick a text-to-speech voice.
  final String languageCode;

  /// Whether the translation is written right-to-left — Urdu, Persian and
  /// Hebrew among others. The Arabic is always laid out right-to-left; this
  /// is about the translation beneath it, which the app would otherwise
  /// render in the app's own direction and align on the wrong edge.
  final bool isRightToLeft;

  /// Number of ayat this edition contains. 6,236 for a complete Qur'an in the
  /// standard Kufan numbering; other numberings exist and the app trusts what
  /// is actually installed.
  final int totalAyah;

  /// Where the text came from. Displayed as attribution.
  final ContentSource source;

  /// Whether the text is a verified edition or a development fixture.
  final ContentVerification verification;

  /// The key reading progress and favourites are stored against.
  ///
  /// Every complete edition of the Qur'an shares one scope, because ayah 2:255
  /// is the same ayah whichever translation renders it: changing translation
  /// keeps your place and your saved ayat rather than starting you over.
  /// Editions that are not the Qur'an — the development fixture — keep their
  /// own scope, so their placeholder progress can never leak into it.
  String get scope => progressScope ?? id;

  /// Overrides [scope]. Null means this edition stands alone.
  final String? progressScope;

  /// True once the edition's text is present in local storage and readable
  /// offline.
  final bool isInstalled;

  /// True when the content source can supply this edition's text — either it
  /// is already installed, or importing it would succeed. Catalog entries whose
  /// dataset has not been added yet report `false` and surface a
  /// "dataset not installed" state rather than an error.
  final bool isAvailable;

  bool get isFixture => verification.isFixture;

  /// Whether the reader can open this edition right now (or after a quick,
  /// automatic first-open import).
  bool get isReadable => isInstalled || isAvailable;

  QuranEdition copyWith({
    bool? isInstalled,
    bool? isAvailable,
    int? totalAyah,
  }) {
    return QuranEdition(
      id: id,
      slug: slug,
      titleEnglish: titleEnglish,
      titleArabic: titleArabic,
      translator: translator,
      translatorArabic: translatorArabic,
      description: description,
      languageName: languageName,
      languageNativeName: languageNativeName,
      languageCode: languageCode,
      isRightToLeft: isRightToLeft,
      totalAyah: totalAyah ?? this.totalAyah,
      source: source,
      verification: verification,
      progressScope: progressScope,
      isInstalled: isInstalled ?? this.isInstalled,
      isAvailable: isAvailable ?? this.isAvailable,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QuranEdition &&
      other.id == id &&
      other.totalAyah == totalAyah &&
      other.isInstalled == isInstalled &&
      other.isAvailable == isAvailable;

  @override
  int get hashCode => Object.hash(id, totalAyah, isInstalled, isAvailable);
}

/// Attribution for an edition's text. Stored with every edition so the app can
/// always say where its content came from.
@immutable
class ContentSource {
  const ContentSource({
    required this.name,
    this.url,
    this.translator,
    this.licence,
    this.retrievedAt,
  });

  /// Human-readable name of the dataset or publisher.
  final String name;

  /// Canonical link to the dataset or publisher.
  final String? url;

  /// Credited translator, when the dataset names one separately.
  final String? translator;

  /// Licence the dataset is distributed under, when known.
  final String? licence;

  /// When the dataset snapshot was taken.
  final DateTime? retrievedAt;

  @override
  bool operator ==(Object other) =>
      other is ContentSource && other.name == name && other.url == url;

  @override
  int get hashCode => Object.hash(name, url);
}
