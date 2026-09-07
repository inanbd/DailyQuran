import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/formatting.dart';
import '../../domain/entities/reading_plan.dart';
import '../../domain/entities/user_preferences.dart';
import '../../domain/services/plan_scheduler.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/progress_bar.dart';
import '../../shared/widgets/settings_group.dart';
import '../today/today_controller.dart';
import 'settings_labels.dart';

/// How much of the Qur'an a reading period asks for.
///
/// The screen is deliberately honest about the arithmetic: each plan shows the
/// rate it works out to *for the edition actually open*, so "in a month" is
/// presented as the 208 ayat a day it really is rather than as an aspiration.
class ReadingPlanScreen extends ConsumerWidget {
  const ReadingPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserPreferences preferences = ref.watch(userPreferencesProvider);
    final TodayState? today = ref.watch(todayControllerProvider).value;
    final ReadingPlan plan = preferences.plan;
    final int total = today?.total ?? 0;

    return AppPage(
      title: 'Reading plan',
      showBackButton: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (today?.portion != null && plan.isPaced) ...<Widget>[
            _PlanStatus(portion: today!.portion!),
            const SizedBox(height: AppSpacing.xl),
          ],
          SettingsGroup(
            title: 'Pace',
            children: <Widget>[
              for (final ReadingPlanKind kind in ReadingPlanKind.values)
                ChoiceRow<ReadingPlanKind>(
                  label: SettingsLabels.planName(kind),
                  description: _rateFor(kind, total),
                  value: kind,
                  groupValue: plan.kind,
                  onChanged: (ReadingPlanKind value) => _choose(ref, value),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            plan.isPaced
                ? 'Miss a few days and nothing is lost or marked read for you — '
                    'what is left is simply spread over the days that remain, so '
                    'the next portion grows a little and the date still holds.'
                : 'One ayah each time you sit down to read, for as long as it '
                    'takes. Nothing to fall behind on.',
            style: AppTypography.reference.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          if (plan.isPaced) ...<Widget>[
            const SizedBox(height: AppSpacing.xl),
            _RebaselineButton(plan: plan),
          ],
        ],
      ),
    );
  }

  /// What a plan works out to per day for the edition open, or a plain
  /// description when nothing is open yet to divide.
  static String _rateFor(ReadingPlanKind kind, int total) {
    if (!kind.isPaced) return 'The steady pace. No end date.';
    final int? perDay = kind.nominalPerDay(total);
    if (perDay == null) return 'The whole Qur’an, spread evenly.';
    return 'About ${Formatting.count(perDay)} '
        '${perDay == 1 ? 'ayah' : 'ayat'} a day.';
  }

  static Future<void> _choose(WidgetRef ref, ReadingPlanKind kind) async {
    final UserPreferences preferences = ref.read(userPreferencesProvider);
    if (preferences.plan.kind == kind) return;

    await ref.read(userPreferencesProvider.notifier).update(
          preferences.copyWith(
            plan: ReadingPlan(
              kind: kind,
              // A plan working towards a date starts its clock the moment it is
              // chosen; one that sets a rate has no clock to start.
              startedOn: kind.isPaced ? ref.read(clockProvider)() : null,
            ),
          ),
        );

    // A reminder counts out the portion, so what is already armed is now
    // describing the old plan.
    await ref.read(notificationPreferencesProvider.notifier).applyToScheduler();
  }
}

/// Where the plan stands: what today asks for, and what date it is holding.
class _PlanStatus extends StatelessWidget {
  const _PlanStatus({required this.portion});

  final ReadingPortion portion;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final DateTime? deadline = portion.deadline;
    final bool behind = portion.periodsBehind > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ReadingProgressBar(
          read: portion.read,
          total: portion.target,
          label: portion.isComplete
              ? 'Today’s portion is done'
              : 'Today · ${Formatting.count(portion.read)} of '
                  '${Formatting.count(portion.target)}',
        ),
        const SizedBox(height: AppSpacing.md),
        if (deadline != null)
          Text(
            behind
                // Named plainly rather than dressed up. The number that follows
                // it is the app's answer to being behind, so the two belong in
                // the same breath.
                ? 'About ${portion.periodsBehind} '
                    '${portion.periodsBehind == 1 ? 'reading' : 'readings'} '
                    'behind. Aiming for ${Formatting.date(deadline)}, with '
                    '${Formatting.count(portion.target)} a day from here.'
                : 'On track for ${Formatting.date(deadline)}, at '
                    '${Formatting.count(portion.target)} a day.',
            style: AppTypography.reference.copyWith(
              color: behind ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        if (portion.projectedCompletion != null &&
            deadline != null &&
            portion.projectedCompletion != deadline) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            // Only ever shown once the date has actually gone: the plan has
            // stopped chasing it and says when it will really finish instead.
            'That date has passed. At this pace the reading finishes around '
            '${Formatting.date(portion.projectedCompletion!)}.',
            style: AppTypography.reference.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Starts a paced plan's clock again from today.
///
/// The escape hatch a deadline needs. Catching up is the point of a paced plan,
/// but someone who put it down for two months should be able to pick it up
/// again without being handed a portion no one could read.
class _RebaselineButton extends ConsumerWidget {
  const _RebaselineButton({required this.plan});

  final ReadingPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        OutlinedButton(
          onPressed: () => _restart(context, ref),
          child: const Text('Start this plan from today'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Keeps everything you have read and moves the finishing date, so a '
          'long gap does not leave you with an impossible portion.',
          style: AppTypography.reference.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ],
    );
  }

  Future<void> _restart(BuildContext context, WidgetRef ref) async {
    final UserPreferences preferences = ref.read(userPreferencesProvider);
    await ref.read(userPreferencesProvider.notifier).update(
          preferences.copyWith(
            plan: plan.copyWith(startedOn: ref.read(clockProvider)()),
          ),
        );
    await ref.read(notificationPreferencesProvider.notifier).applyToScheduler();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The plan now runs from today.')),
    );
  }
}
