import 'package:flutter/material.dart';

import '../../app/edition_providers.dart';
import '../../core/utils/formatting.dart';
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/reading_progress.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'progress_bar.dart';

/// An edition as it appears in the library: translation name, translator,
/// language, size, and progress once started.
class EditionCard extends StatelessWidget {
  const EditionCard({
    required this.entry,
    required this.onTap,
    this.isCurrent = false,
    this.action,
    super.key,
  });

  final LibraryEntry entry;
  final VoidCallback onTap;

  /// Marks the edition the Today screen is currently reading from.
  final bool isCurrent;

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final QuranEdition edition = entry.edition;
    final ReadingProgress progress = entry.progress;
    final bool started = entry.hasStarted;

    return Semantics(
      button: true,
      label: _semanticLabel(edition, progress, started),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(
              color: isCurrent ? colors.accent : colors.border,
              width: isCurrent ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      edition.titleEnglish,
                      style: AppTypography.sectionTitle.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  if (isCurrent) const _CurrentBadge(),
                ],
              ),
              if (edition.titleArabic.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Text(
                    edition.titleArabic,
                    locale: const Locale('ar'),
                    style: AppTypography.arabicTitle.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                _subtitle(edition),
                style: AppTypography.metadata.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              if (edition.isFixture) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                _Tag(label: 'Development data', color: colors.warm),
              ] else if (!edition.isReadable) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                _Tag(label: 'Dataset not installed', color: colors.textSecondary),
              ],
              if (started) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                ReadingProgressBar(
                  read: progress.totalRead,
                  total: progress.totalAyah,
                  label: '${Formatting.count(progress.totalRead)} read',
                  showPercentage: true,
                ),
              ],
              if (action != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle(QuranEdition edition) {
    final List<String> parts = <String>[
      if (edition.translator.isNotEmpty) edition.translator,
      edition.languageName,
      '${Formatting.count(edition.totalAyah)} ayat',
    ];
    return parts.join(' · ');
  }

  static String _semanticLabel(
    QuranEdition edition,
    ReadingProgress progress,
    bool started,
  ) {
    final StringBuffer buffer = StringBuffer(edition.titleEnglish);
    if (edition.translator.isNotEmpty) buffer.write(', ${edition.translator}');
    buffer.write(', ${edition.languageName}');
    buffer.write(', ${Formatting.count(edition.totalAyah)} ayat');
    if (started) {
      buffer.write(
        ', ${Formatting.count(progress.totalRead)} read, '
        '${Formatting.percent(progress.percentage)} complete',
      );
    }
    if (edition.isFixture) buffer.write(', development data');
    if (!edition.isReadable) buffer.write(', dataset not installed');
    return buffer.toString();
  }
}

class _CurrentBadge extends StatelessWidget {
  const _CurrentBadge();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Current',
        style: AppTypography.progressMeta.copyWith(color: colors.accent),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppTypography.progressMeta.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
