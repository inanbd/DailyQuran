import 'package:flutter/material.dart';

import '../../domain/entities/ayah.dart';
import '../../domain/entities/enums.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Renders one ayah as a page of the mushaf.
///
/// The Arabic is shown first and always laid out right-to-left, regardless of
/// the app's own direction. Text is passed through untouched — this widget only
/// decides how it looks, never what it says.
///
/// There is no control here for speaking the Arabic aloud, and that is
/// deliberate: recitation of the Qur'an is its own discipline, and a
/// text-to-speech engine does not perform it. Only the translation can be
/// spoken.
///
/// The listen and favourite controls are passed in rather than read from a
/// provider, so this stays presentational and any screen can mount it without
/// wiring up state.
class AyahView extends StatelessWidget {
  const AyahView({
    required this.ayah,
    required this.languageMode,
    required this.textScale,
    this.showTransliteration = false,
    this.translationIsRightToLeft = false,
    this.showReference = true,
    this.onSpeakTranslation,
    this.isSpeakingTranslation = false,
    this.onToggleFavourite,
    this.isFavourite = false,
    super.key,
  });

  final Ayah ayah;
  final LanguageMode languageMode;

  /// The reader's text-size preference. Platform dynamic type is applied on top
  /// of this by the framework, so both settings compose.
  final double textScale;

  /// Whether to show the transliteration, when the edition carries one.
  final bool showTransliteration;

  /// Whether the translation is written right-to-left, e.g. Urdu.
  final bool translationIsRightToLeft;

  final bool showReference;

  /// Speaks the translation, or stops it. Null hides the control, which is what
  /// happens on a device with no voice for the translation's language.
  final VoidCallback? onSpeakTranslation;

  /// Whether this ayah's translation is the utterance currently being spoken.
  final bool isSpeakingTranslation;

  /// Saves or unsaves this ayah. Null hides the control.
  final VoidCallback? onToggleFavourite;

  final bool isFavourite;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;

    final bool wantsArabic = languageMode.showsArabic && ayah.hasArabic;
    final bool wantsTranslation =
        languageMode.showsTranslation && ayah.hasTranslation;

    // If the reader's chosen language is missing for this entry, fall back to
    // whatever the source does have rather than showing an empty page.
    final bool showArabic = wantsArabic || (!wantsTranslation && ayah.hasArabic);
    final bool showTranslation =
        wantsTranslation || (!wantsArabic && ayah.hasTranslation);
    final bool showLatin = showTransliteration && ayah.hasTransliteration;

    // Speaking is only ever offered for text that is actually on screen.
    final VoidCallback? speak = showTranslation ? onSpeakTranslation : null;
    final bool hasActions = speak != null || onToggleFavourite != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showArabic) _ArabicText(text: ayah.arabicText!, scale: textScale),
        if (showLatin) ...<Widget>[
          SizedBox(height: showArabic ? AppSpacing.md : 0),
          _TransliterationText(text: ayah.transliteration!, scale: textScale),
        ],
        if ((showArabic || showLatin) && showTranslation)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: AyahDivider(),
          ),
        if (showTranslation)
          _TranslationText(
            text: ayah.translationText!,
            scale: textScale,
            isRightToLeft: translationIsRightToLeft,
          ),
        if (!showArabic && !showTranslation)
          Text(
            'This entry has no text in the selected language.',
            style: AppTypography.body.copyWith(color: colors.textSecondary),
          ),
        if (ayah.sajda) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          const _SajdaNote(),
        ],
        if (hasActions) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _AyahActions(
            onSpeak: speak,
            isSpeaking: isSpeakingTranslation,
            onToggleFavourite: onToggleFavourite,
            isFavourite: isFavourite,
          ),
        ],
        if (showReference) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          _ReferenceBlock(ayah: ayah),
        ],
      ],
    );
  }
}

/// A verse the source marks as an ayah of prostration.
///
/// Shown only when the dataset says so; the app never works one out for itself.
class _SajdaNote extends StatelessWidget {
  const _SajdaNote();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return Row(
      children: <Widget>[
        Icon(Icons.star_outline, size: 16, color: colors.warm),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'This source marks this as an ayah of prostration (sajdah).',
            style: AppTypography.reference.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Listen and favourite, sitting directly beneath the passage they act on.
///
/// Left-aligned with the text rather than pushed to the far edge, so the pair
/// reads as belonging to the ayah above them.
class _AyahActions extends StatelessWidget {
  const _AyahActions({
    required this.onSpeak,
    required this.isSpeaking,
    required this.onToggleFavourite,
    required this.isFavourite,
  });

  final VoidCallback? onSpeak;
  final bool isSpeaking;
  final VoidCallback? onToggleFavourite;
  final bool isFavourite;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: <Widget>[
        if (onSpeak != null)
          _ActionButton(
            icon: isSpeaking ? Icons.stop_rounded : Icons.volume_up_outlined,
            // The label says what pressing it will do, which is what a screen
            // reader announces.
            tooltip:
                isSpeaking ? 'Stop reading aloud' : 'Listen to the translation',
            color: isSpeaking ? colors.accent : colors.textSecondary,
            onPressed: onSpeak,
          ),
        if (onToggleFavourite != null)
          _ActionButton(
            icon: isFavourite ? Icons.favorite : Icons.favorite_border,
            tooltip:
                isFavourite ? 'Remove from favourites' : 'Save to favourites',
            color: isFavourite ? colors.accent : colors.textSecondary,
            onPressed: onToggleFavourite,
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 22, color: color),
      tooltip: tooltip,
      constraints: const BoxConstraints(
        minWidth: AppSpacing.minTapTarget,
        minHeight: AppSpacing.minTapTarget,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// A hairline rule with a small warm centre mark — the one decorative flourish
/// in the app, standing in for the divider between the text and its
/// translation.
class AyahDivider extends StatelessWidget {
  const AyahDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return ExcludeSemantics(
      child: Row(
        children: <Widget>[
          Expanded(child: Divider(color: colors.border, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: colors.warm,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(child: Divider(color: colors.border, height: 1)),
        ],
      ),
    );
  }
}

class _ArabicText extends StatelessWidget {
  const _ArabicText({required this.text, required this.scale});

  final String text;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return Directionality(
      // Arabic is laid out right-to-left even when the app itself is not.
      textDirection: TextDirection.rtl,
      // `locale` drives font and glyph selection for this run. Flutter does
      // not currently expose a per-node screen-reader language, so the reader's
      // system voice setting decides how the Arabic is spoken.
      child: Text(
        text,
        textAlign: TextAlign.right,
        locale: const Locale('ar'),
        style: AppTypography.arabicBody.copyWith(
          color: colors.textPrimary,
          fontSize: AppTypography.arabicBody.fontSize! * scale,
        ),
      ),
    );
  }
}

class _TransliterationText extends StatelessWidget {
  const _TransliterationText({required this.text, required this.scale});

  final String text;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return Text(
      text,
      style: AppTypography.transliterationBody.copyWith(
        color: colors.textSecondary,
        fontSize: AppTypography.transliterationBody.fontSize! * scale,
      ),
    );
  }
}

class _TranslationText extends StatelessWidget {
  const _TranslationText({
    required this.text,
    required this.scale,
    required this.isRightToLeft,
  });

  final String text;
  final double scale;

  /// An Urdu or Persian translation reads right-to-left and has to be laid out
  /// and aligned that way, whatever direction the app itself is running in.
  final bool isRightToLeft;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final Widget rendered = Text(
      text,
      textAlign: isRightToLeft ? TextAlign.right : TextAlign.start,
      style: AppTypography.translationBody.copyWith(
        color: colors.textPrimary,
        fontSize: AppTypography.translationBody.fontSize! * scale,
      ),
    );
    if (!isRightToLeft) return rendered;
    return Directionality(textDirection: TextDirection.rtl, child: rendered);
  }
}

/// Citation, juz' and attribution — everything needed to trace the text back to
/// its source.
class _ReferenceBlock extends StatelessWidget {
  const _ReferenceBlock({required this.ayah});

  final Ayah ayah;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final TextStyle labelStyle = AppTypography.overline.copyWith(
      color: colors.textSecondary,
    );
    final TextStyle valueStyle = AppTypography.reference.copyWith(
      color: colors.textPrimary,
    );
    final TextStyle mutedStyle = AppTypography.reference.copyWith(
      color: colors.textSecondary,
    );

    final List<Widget> rows = <Widget>[];

    if (ayah.reference != null) {
      rows.add(Text(ayah.reference!, style: valueStyle));
    }
    if (ayah.surahNameEnglish != null) {
      rows.add(Text('Surah: ${ayah.surahNameEnglish}', style: mutedStyle));
    }
    if (ayah.juz != null) {
      rows.add(Text('Juz’ ${ayah.juz}', style: mutedStyle));
    }
    if (ayah.page != null) {
      rows.add(Text('Page ${ayah.page}', style: mutedStyle));
    }
    if (ayah.source != null) {
      rows.add(Text('Source: ${ayah.source}', style: mutedStyle));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Divider(color: colors.border, height: 1),
        const SizedBox(height: AppSpacing.lg),
        Text('REFERENCE', style: labelStyle),
        const SizedBox(height: AppSpacing.sm),
        for (final Widget row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: row,
          ),
      ],
    );
  }
}
