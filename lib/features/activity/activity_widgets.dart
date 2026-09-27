import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/utils/formatting.dart';
import '../../domain/entities/reading_day.dart';
import '../../domain/services/daily_goal.dart';
import '../../domain/services/encouragement.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/progress_bar.dart';
import 'reading_activity.dart';

/// "12 min" in a stat or a caption, where "under a minute" would not fit.
String _compactTime(int seconds) =>
    seconds < 60 ? '0 min' : Encouragement.readingTimeWords(seconds);

/// The sentence that says what earns a day its place in the streak.
String streakRule(DailyGoal goal) {
  final String time =
      'read for ${Encouragement.readingTimeWords(goal.minutes * 60)}';
  const String plan = 'meet your plan’s goal';
  final String what = goal.hasTimeGoal && goal.hasPlan
      ? '$time or $plan'
      : goal.hasTimeGoal
          ? time
          : goal.hasPlan
              ? plan
              : 'read your Daily Ayah';
  return 'A day counts towards your streak when you $what.';
}

/// The reader's reading at a glance, for the Progress tab: their streak,
/// today's and the week's reading time, and the last seven days.
class ReadingSummaryCard extends ConsumerWidget {
  const ReadingSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ReadingSummary? summary = ref.watch(readingSummaryProvider).value;
    if (summary == null) return const SizedBox.shrink();

    final AppColors colors = context.colors;
    final TextStyle note =
        AppTypography.reference.copyWith(color: colors.textSecondary);
    final int goalMinutes = summary.goal.minutes;

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
          _StatsRow(summary: summary),
          if (summary.goal.hasTimeGoal) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            ReadingProgressBar(
              read: summary.today.minutes,
              total: goalMinutes,
              label: summary.today.minutes >= goalMinutes
                  ? 'Today’s reading time is done'
                  : 'Today · ${summary.today.minutes} of $goalMinutes min',
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _WeekStrip(days: summary.week),
          const SizedBox(height: AppSpacing.lg),
          Text(
            Encouragement.weekTrend(
              week: summary.weekSeconds,
              previous: summary.previousWeekSeconds,
            ),
            style: AppTypography.body.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(streakRule(summary.goal), style: note),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => context.go(Routes.settingsReading),
              child: Text(
                summary.goal.hasTimeGoal
                    ? 'Change daily reading time'
                    : 'Set a daily reading time',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Streak · today · last seven days.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.summary});

  final ReadingSummary summary;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final List<(String, String)> cells = <(String, String)>[
      (
        Formatting.count(summary.streak),
        summary.streak == 1 ? 'day in a row' : 'days in a row',
      ),
      (_compactTime(summary.today.seconds), 'read today'),
      (_compactTime(summary.weekSeconds), 'last 7 days'),
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
              child: Semantics(
                label: '${cells[i].$1} ${cells[i].$2}',
                excludeSemantics: true,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
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
            ),
          ],
        ],
      ),
    );
  }
}

/// The last seven days, today last: a filled mark with a tick where the goal
/// was met, a soft ring where there was reading short of it, and an empty
/// outline where there was none. Each is told apart by its shape as well as
/// its colour, and each is read out in full.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.days});

  final List<ReadingDay> days;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return Row(
      children: <Widget>[
        for (int i = 0; i < days.length; i++)
          Expanded(
            child: _DayMark(
              day: days[i],
              isToday: i == days.length - 1,
              colors: colors,
            ),
          ),
      ],
    );
  }
}

class _DayMark extends StatelessWidget {
  const _DayMark({
    required this.day,
    required this.isToday,
    required this.colors,
  });

  final ReadingDay day;
  final bool isToday;
  final AppColors colors;

  static const double _size = 28;

  @override
  Widget build(BuildContext context) {
    final bool read = day.seconds > 0;
    final String state = day.goalMet
        ? 'goal met'
        : read
            ? 'some reading'
            : 'no reading';
    final String time =
        read ? ', ${Encouragement.readingTimeWords(day.seconds)}' : '';

    return Semantics(
      label: '${isToday ? 'Today' : Formatting.fullWeekday(day.day.weekday)}: '
          '$state$time',
      excludeSemantics: true,
      child: Column(
        children: <Widget>[
          Text(
            Formatting.shortWeekday(day.day.weekday),
            style: AppTypography.progressMeta.copyWith(
              color: isToday ? colors.textPrimary : colors.textSecondary,
              fontWeight: isToday ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: day.goalMet
                  ? colors.accent
                  : read
                      ? colors.accentSoft
                      : Colors.transparent,
              border: Border.all(
                color: day.goalMet || read ? colors.accent : colors.border,
                width: read && !day.goalMet ? 2 : 1,
              ),
            ),
            child: day.goalMet
                ? Icon(Icons.check, size: 16, color: colors.onAccent)
                : null,
          ),
        ],
      ),
    );
  }
}

/// Today's reading time against the reader's goal, for the Today screen.
/// Nothing at all without a goal: the page stays about the ayah.
class ReadingTimeGoalBar extends ConsumerWidget {
  const ReadingTimeGoalBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ReadingSummary? summary = ref.watch(readingSummaryProvider).value;
    if (summary == null || !summary.goal.hasTimeGoal) {
      return const SizedBox.shrink();
    }
    final int goal = summary.goal.minutes;
    final int minutes = summary.today.minutes;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: ReadingProgressBar(
        read: minutes,
        total: goal,
        label: minutes >= goal
            ? 'Today’s reading time is done'
            : 'Reading time · $minutes of $goal min today',
      ),
    );
  }
}
