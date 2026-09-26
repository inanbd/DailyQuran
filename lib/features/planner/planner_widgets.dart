/// Pieces of the planner shared by the planner screen, the goal screen a
/// plan's reminder opens, and the Progress tab — so the same goal always looks
/// and reads the same wherever it appears.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/utils/formatting.dart';
import '../../domain/entities/ayah.dart';
import '../../domain/entities/reading_track.dart';
import '../../domain/services/plan_scheduler.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/ornaments.dart';
import '../today/today_controller.dart';
import 'plan_status.dart';

/// "202 ayat" — a count with the right word for it.
String ayatCount(int count) =>
    '${Formatting.count(count)} ${count == 1 ? 'ayah' : 'ayat'}';

/// Puts the plan's reading on screen and goes to it.
///
/// The router is taken before switching: the switch rebuilds whatever plan
/// view the button sits in, which can take the button — and its context —
/// with it.
Future<void> continuePlanReading(BuildContext context, WidgetRef ref) async {
  final GoRouter router = GoRouter.of(context);
  await ref.read(todayControllerProvider.notifier).switchTrack(ReadingTrack.plan);
  router.go(Routes.today);
}

/// The one sentence that says how the plan is going, in plain words.
String standingSentence(PlanStatus status) {
  switch (status.standing) {
    case PlanStanding.complete:
      return 'You finished the whole Qur’an. Alhamdulillah!';
    case PlanStanding.doneToday:
      return 'Today’s goal is done. Well done!';
    case PlanStanding.late:
      final DateTime? projected = status.goal.projectedCompletion;
      return projected == null
          ? 'Your finish date has passed. Keep going, or plan again from today.'
          : 'Your finish date has passed. At this pace you will finish around '
              '${Formatting.date(projected)}.';
    case PlanStanding.behind:
      return 'You missed some reading, so today’s goal is a little bigger. '
          'You can still finish on time.';
    case PlanStanding.ahead:
      return 'You read extra before, so today’s goal is smaller.';
    case PlanStanding.onTrack:
      return 'You are on track.';
  }
}

IconData _standingIcon(PlanStanding standing) {
  switch (standing) {
    case PlanStanding.complete:
    case PlanStanding.doneToday:
      return Icons.check_circle;
    case PlanStanding.late:
      return Icons.event_busy;
    case PlanStanding.behind:
      return Icons.update;
    case PlanStanding.ahead:
      return Icons.bolt;
    case PlanStanding.onTrack:
      return Icons.thumb_up_alt_outlined;
  }
}

/// Today's goal as a ring: the goal in the middle, what is read so far as the
/// fill, and the rest spelled out beneath.
class GoalRing extends StatelessWidget {
  const GoalRing({required this.goal, this.size = 168, super.key});

  final ReadingPortion goal;
  final double size;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final bool done = goal.isComplete;
    final String caption = goal.target <= 0
        // The whole Qur'an is read: there is no goal left to count.
        ? 'Nothing left to read'
        : done
            ? '${ayatCount(goal.read)} read today'
            : '${Formatting.count(goal.read)} read · '
                '${Formatting.count(goal.remaining)} to go';

    return Semantics(
      label: done
          ? 'Today’s goal is done. $caption.'
          : 'Today’s goal: ${ayatCount(goal.target)}. $caption.',
      excludeSemantics: true,
      child: Column(
        children: <Widget>[
          ProgressRing(
            progress: goal.fraction,
            size: size,
            strokeWidth: size / 16,
            trackColor: colors.accentSoft,
            fillColor: colors.accent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (done)
                  Icon(Icons.check_rounded, size: size / 4, color: colors.accent)
                else
                  Text(
                    Formatting.count(goal.target),
                    style: AppTypography.statNumeral.copyWith(
                      color: colors.textPrimary,
                      fontSize: size / 4.6,
                    ),
                  ),
                Text(
                  done ? 'Done!' : (goal.target == 1 ? 'ayah today' : 'ayat today'),
                  style: AppTypography.metadata.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: AppTypography.metadata.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// The plan at a glance: how much of the Qur'an, how many days, which day.
class PlanStatsRow extends StatelessWidget {
  const PlanStatsRow({required this.status, super.key});

  final PlanStatus status;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final DateTime? finish = status.finishDate;
    final List<(String, String)> cells = <(String, String)>[
      (Formatting.percent(status.progress.percentage), 'Qur’an read'),
      (
        Formatting.count(status.daysLeft),
        status.daysLeft == 1 ? 'day left' : 'days left',
      ),
      (
        finish == null
            ? '—'
            : Formatting.shortDate(finish, today: status.today),
        'finish date',
      ),
    ];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < cells.length; i++) ...<Widget>[
            if (i > 0)
              VerticalDivider(
                width: 1,
                thickness: 1,
                indent: 4,
                endIndent: 4,
                color: colors.border,
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      cells[i].$1,
                      textAlign: TextAlign.center,
                      style: AppTypography.sectionTitle.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cells[i].$2,
                      textAlign: TextAlign.center,
                      style: AppTypography.progressMeta.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// How the plan is going, as an icon and one plain sentence.
class PlanStandingNote extends StatelessWidget {
  const PlanStandingNote({required this.status, super.key});

  final PlanStatus status;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final PlanStanding standing = status.standing;
    final bool good = standing == PlanStanding.complete ||
        standing == PlanStanding.doneToday ||
        standing == PlanStanding.onTrack ||
        standing == PlanStanding.ahead;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: good ? colors.accentSoft : colors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: <Widget>[
          ExcludeSemantics(
            child: Icon(
              _standingIcon(standing),
              size: 18,
              color: good ? colors.accent : colors.textPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              standingSentence(status),
              style: AppTypography.reference.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the plan's reading picks up: "Al-Baqarah · 2:142".
class NextAyahLine extends StatelessWidget {
  const NextAyahLine({required this.ayah, super.key});

  final Ayah ayah;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final String where = <String>[
      if (ayah.surahNameEnglish != null) ayah.surahNameEnglish!,
      ayah.verseKey,
    ].join(' · ');

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        ExcludeSemantics(
          child: Icon(Icons.bookmark_outline, size: 16, color: colors.warm),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            'You will start at $where',
            textAlign: TextAlign.center,
            style: AppTypography.metadata.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// The big button every plan view leads to.
class ContinueReadingButton extends ConsumerWidget {
  const ContinueReadingButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => continuePlanReading(context, ref),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
        ),
        icon: const Icon(Icons.menu_book, size: 20),
        label: const Text('Continue reading'),
      ),
    );
  }
}

/// A small-caps heading led by a gold star, trailed by a fading hairline.
class OrnateHeading extends StatelessWidget {
  const OrnateHeading(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return Row(
      children: <Widget>[
        EightPointStar(size: 9, color: colors.warm),
        const SizedBox(width: AppSpacing.sm),
        Semantics(
          header: true,
          child: Text(
            title.toUpperCase(),
            style: AppTypography.overline.copyWith(
              color: colors.textSecondary,
              letterSpacing: 1.6,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  colors.warm.withValues(alpha: 0.45),
                  colors.warm.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The framed card the plan's goal sits in: a soft gradient, a gold hairline
/// border, and ornamental rules above and below.
class OrnateCard extends StatelessWidget {
  const OrnateCard({required this.title, required this.child, super.key});

  /// Set in spaced small caps between the upper ornaments.
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final Color hairline = colors.warm.withValues(alpha: 0.55);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[colors.surface, colors.surfaceMuted],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OrnamentalDivider(color: hairline),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              header: true,
              child: Text(
                title.toUpperCase(),
                textAlign: TextAlign.center,
                style: AppTypography.overline.copyWith(
                  color: colors.textSecondary,
                  letterSpacing: 2.4,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            child,
            const SizedBox(height: AppSpacing.lg),
            OrnamentalDivider(color: hairline, starSize: 7),
          ],
        ),
      ),
    );
  }
}

/// The name of each plan, as the reader chooses between them.
abstract final class PlanLabels {
  static const String month = 'Finish in 1 month';
  static const String year = 'Finish in 1 year';
  static const String custom = 'Pick a finish date';
}

/// A goal described in words.
extension GoalWords on ReadingPortion {
  /// "12 of 202 ayat".
  String get progressWords =>
      '${Formatting.count(read)} of ${ayatCount(target)}';
}
