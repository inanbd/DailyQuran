import 'package:flutter/material.dart';

import '../../app/edition_providers.dart';
import '../../domain/entities/quran_edition.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// An edition as it appears in the library: translation name, translator and
/// language, and nothing else.
///
/// Deliberately says nothing about progress or length. Every complete edition
/// shares one reading scope, so a progress bar on each card would repeat the
/// same figure down the whole list, and the ayah count is the same 6,236 on
/// every one of them. The Progress screen is where the reading is measured.
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

    return Semantics(
      button: true,
      label: _semanticLabel(edition),
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
      edition.languageLabel,
    ];
    return parts.join(' · ');
  }

  static String _semanticLabel(QuranEdition edition) {
    final StringBuffer buffer = StringBuffer(edition.titleEnglish);
    if (edition.translator.isNotEmpty) buffer.write(', ${edition.translator}');
    buffer.write(', ${edition.languageLabel}');
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
