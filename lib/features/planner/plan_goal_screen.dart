import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/ornaments.dart';
import '../../shared/widgets/state_views.dart';
import 'plan_status.dart';
import 'planner_widgets.dart';

/// Today's goal, shown first when the reader opens their plan's reminder.
///
/// A plan's reminder is not a single ayah to open and be done with, so it
/// lands here rather than on the reading: what today asks for, how much of it
/// is done, how the plan is going — and one button to begin. Nothing is
/// marked read by arriving here.
class PlanGoalScreen extends ConsumerWidget {
  const PlanGoalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = context.colors;
    final AsyncValue<PlanStatus?> status = ref.watch(planStatusProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: ReadingColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: IconButton(
                    onPressed: () => context.go(Routes.today),
                    icon: const Icon(Icons.close),
                    color: colors.textSecondary,
                    tooltip: 'Close',
                  ),
                ),
              ),
              Expanded(
                child: status.when(
                  skipLoadingOnReload: true,
                  loading: () => const LoadingView(),
                  error: (Object error, StackTrace stack) => ErrorStateView(
                    message: 'Your plan could not be loaded. Your reading is '
                        'safe.',
                    onRetry: () => ref.invalidate(planStatusProvider),
                  ),
                  data: (PlanStatus? value) => value == null
                      ? const _NoPlan()
                      : _Goal(status: value),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Goal extends StatelessWidget {
  const _Goal({required this.status});

  final PlanStatus status;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final Color hairline = colors.warm.withValues(alpha: 0.55);
    final bool readingLeft = status.standing != PlanStanding.complete &&
        status.standing != PlanStanding.doneToday;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OrnamentalDivider(color: hairline),
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  header: true,
                  child: Text(
                    'Today’s goal',
                    textAlign: TextAlign.center,
                    style: AppTypography.pageTitle.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Your Qur’an plan',
                  textAlign: TextAlign.center,
                  style: AppTypography.metadata.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Center(child: GoalRing(goal: status.goal, size: 200)),
                const SizedBox(height: AppSpacing.lg),
                if (readingLeft && status.nextAyah != null) ...<Widget>[
                  NextAyahLine(ayah: status.nextAyah!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                PlanStandingNote(status: status),
                const SizedBox(height: AppSpacing.xl),
                PlanStatsRow(status: status),
                const SizedBox(height: AppSpacing.xl),
                OrnamentalDivider(color: hairline, starSize: 7),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.sm,
            AppSpacing.gutter,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const ContinueReadingButton(),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: () => context.go(Routes.planner),
                child: const Text('See my plan'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Reached from a reminder armed before the plan was stopped.
class _NoPlan extends StatelessWidget {
  const _NoPlan();

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Icons.flag_outlined,
      title: 'No plan right now',
      message: 'You can make a new plan any time from the Progress tab.',
      action: FilledButton(
        onPressed: () => context.go(Routes.today),
        child: const Text('Go to today’s ayah'),
      ),
    );
  }
}
