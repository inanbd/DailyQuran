import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/edition_providers.dart';
import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../core/utils/formatting.dart';
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/entities/reading_track.dart';
import '../../domain/entities/user_preferences.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/progress_bar.dart';
import '../../shared/widgets/state_views.dart';
import '../activity/activity_widgets.dart';
import '../planner/plan_status.dart';
import '../planner/planner_widgets.dart';
import '../today/today_controller.dart';

/// Reading progress: the reader's own reading first — their streak and time
/// spent reading — then the two readings of the Qur'an.
///
/// The streak is there to encourage, never to scold: it counts up, and a
/// missed day simply starts it again without comment.
///
/// The reader's two readings are kept apart here as everywhere else: the plan,
/// with today's goal, and the Daily Ayah. Each has its own way back in.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LibraryEntry>> started =
        ref.watch(startedReadingsProvider);
    final PlanStatus? plan = ref.watch(planStatusProvider).value;
    final bool hasEdition = ref.watch(
          userPreferencesProvider
              .select((UserPreferences prefs) => prefs.currentEditionId),
        ) !=
        null;

    return AppPage(
      title: 'Your Progress',
      child: started.when(
        loading: () => const LoadingView(),
        error: (Object error, StackTrace stack) => ErrorStateView(
          message: 'Your progress could not be loaded.',
          onRetry: () => ref.invalidate(libraryProvider),
        ),
        data: (List<LibraryEntry> entries) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (hasEdition) ...<Widget>[
                const OrnateHeading('Your reading'),
                const SizedBox(height: AppSpacing.md),
                const ReadingSummaryCard(),
                const SizedBox(height: AppSpacing.xxl),
                const OrnateHeading('My plan'),
                const SizedBox(height: AppSpacing.md),
                if (plan != null)
                  _PlanCard(status: plan)
                else
                  const _MakePlanCard(),
                const SizedBox(height: AppSpacing.xxl),
              ],
              const OrnateHeading('Daily Ayah'),
              const SizedBox(height: AppSpacing.md),
              if (entries.isEmpty)
                EmptyStateView(
                  icon: Icons.donut_large_outlined,
                  message: 'Your reading progress will appear here once you '
                      'start reading.',
                  action: FilledButton(
                    onPressed: () => context.go(Routes.library),
                    child: const Text('Open the library'),
                  ),
                )
              else
                for (final LibraryEntry entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _ProgressCard(entry: entry),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// The plan at a glance: today's goal, the whole Qur'an, and the finish date.
class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.status});

  final PlanStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = context.colors;
    final ReadingProgress progress = status.progress;
    final DateTime? finish = status.finishDate;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.warm.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (finish != null)
            Text(
              'Finish by ${Formatting.date(finish)}',
              style: AppTypography.sectionTitle.copyWith(
                color: colors.textPrimary,
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            status.daysLeft == 1
                ? '1 day left'
                : '${Formatting.count(status.daysLeft)} days left',
            style: AppTypography.metadata.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          ReadingProgressBar(
            read: status.goal.read,
            total: status.goal.target,
            label: status.goal.isComplete
                ? 'Today’s goal is done'
                : 'Today’s goal · ${status.goal.progressWords}',
          ),
          const SizedBox(height: AppSpacing.lg),
          ReadingProgressBar(
            read: progress.totalRead,
            total: progress.totalAyah,
            label: 'Whole Qur’an · ${Formatting.count(progress.totalRead)} of '
                '${Formatting.count(progress.totalAyah)}',
            showPercentage: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          PlanStandingNote(status: status),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: () => continuePlanReading(context, ref),
            child: const Text('Continue reading'),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: () => context.go(Routes.planner),
            child: const Text('Open the planner'),
          ),
        ],
      ),
    );
  }
}

/// An invitation to make a plan, for a reader who has none.
class _MakePlanCard extends StatelessWidget {
  const _MakePlanCard();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[colors.surface, colors.surfaceMuted],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.warm.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Finish the whole Qur’an by a date',
            style: AppTypography.sectionTitle.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Make a plan and get a small goal for each day. It keeps its own '
            'progress, separate from your Daily Ayah.',
            style: AppTypography.reference.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: () => context.go(Routes.planner),
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('Make a plan'),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends ConsumerWidget {
  const _ProgressCard({required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = context.colors;
    final QuranEdition edition = entry.edition;
    final ReadingProgress progress = entry.progress;
    final bool isCurrent = ref.watch(
          userPreferencesProvider
              .select((UserPreferences prefs) => prefs.currentEditionId),
        ) ==
        edition.id;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            edition.isFixture ? edition.titleEnglish : 'The Qur’an',
            style: AppTypography.sectionTitle.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${Formatting.count(progress.totalRead)} of '
            '${Formatting.count(progress.totalAyah)} ayat · '
            'reading ${edition.titleEnglish}',
            style: AppTypography.metadata.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          ReadingProgressBar(
            read: progress.totalRead,
            total: progress.totalAyah,
            label: Formatting.percent(progress.percentage),
          ),
          const SizedBox(height: AppSpacing.lg),
          _ProgressDetails(progress: progress),
          const SizedBox(height: AppSpacing.lg),
          if (progress.isComplete)
            OutlinedButton(
              onPressed: () => context.go(Routes.edition(edition.id)),
              child: const Text('Completed'),
            )
          else
            FilledButton(
              onPressed: () => _continueReading(context, ref, isCurrent),
              child: const Text('Continue reading'),
            ),
        ],
      ),
    );
  }

  Future<void> _continueReading(
    BuildContext context,
    WidgetRef ref,
    bool isCurrent,
  ) async {
    // Taken first: what follows rebuilds this screen underneath us.
    final GoRouter router = GoRouter.of(context);
    if (!isCurrent) {
      await ref
          .read(userPreferencesProvider.notifier)
          .setCurrentEdition(entry.edition.id);
      await ref
          .read(notificationPreferencesProvider.notifier)
          .applyToScheduler();
    }
    // This card is the Daily Ayah's, so that is the reading it opens.
    await ref
        .read(todayControllerProvider.notifier)
        .switchTrack(ReadingTrack.daily);
    router.go(Routes.today);
  }
}

/// Started date, pace and estimated completion — each shown only when it can
/// be stated meaningfully.
class _ProgressDetails extends StatelessWidget {
  const _ProgressDetails({required this.progress});

  final ReadingProgress progress;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final TextStyle style = AppTypography.reference.copyWith(
      color: colors.textSecondary,
    );

    final List<String> lines = <String>[
      if (progress.startedAt != null)
        'Started ${Formatting.date(progress.startedAt!)}',
      if (progress.pacePerDay != null)
        'Reading pace: ${_pace(progress.pacePerDay!)}',
      if (progress.estimatedCompletion != null)
        'Estimated completion: '
            '${Formatting.date(progress.estimatedCompletion!)}',
      if (progress.completedAt != null)
        'Completed ${Formatting.date(progress.completedAt!)}',
    ];

    if (lines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final String line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(line, style: style),
          ),
      ],
    );
  }

  static String _pace(double perDay) {
    if (perDay >= 1) {
      final String value = perDay == perDay.roundToDouble()
          ? perDay.round().toString()
          : perDay.toStringAsFixed(1);
      return '$value ayat/day';
    }
    final double perWeek = perDay * 7;
    return '${perWeek.toStringAsFixed(1)} ayat/week';
  }
}
