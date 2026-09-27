import 'package:flutter/material.dart';

import '../../domain/services/encouragement.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/ornaments.dart';

/// A word of congratulation: what the reader did, said plainly, and one
/// button to carry on.
///
/// Several earned at once — a reading time reached that also completed a
/// streak — share one sheet rather than arriving one after another.
class CelebrationSheet extends StatelessWidget {
  const CelebrationSheet({required this.achievements, super.key});

  final List<Achievement> achievements;

  /// Shows [achievements] and completes when the reader dismisses them.
  static Future<void> show(
    BuildContext context,
    List<Achievement> achievements,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.colors.surface,
      builder: (BuildContext context) =>
          CelebrationSheet(achievements: achievements),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final Color hairline = colors.warm.withValues(alpha: 0.55);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(child: EightPointStar(size: 36, color: colors.warm)),
            const SizedBox(height: AppSpacing.lg),
            for (int i = 0; i < achievements.length; i++) ...<Widget>[
              if (i > 0) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                OrnamentalDivider(color: hairline, starSize: 7),
                const SizedBox(height: AppSpacing.lg),
              ],
              Semantics(
                header: true,
                child: Text(
                  achievements[i].title,
                  textAlign: TextAlign.center,
                  style: AppTypography.pageTitle.copyWith(
                    color: colors.accent,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                achievements[i].message,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(
                  color: colors.textPrimary,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
