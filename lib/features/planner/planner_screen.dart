import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../core/utils/formatting.dart';
import '../../domain/entities/reading_plan.dart';
import '../../domain/entities/user_preferences.dart';
import '../../domain/repositories/notification_scheduler.dart';
import '../../domain/services/encouragement.dart';
import '../../domain/services/reading_pace.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/settings_group.dart';
import '../../shared/widgets/state_views.dart';
import '../settings/reminder_permission_flow.dart';
import '../settings/reminder_time_rows.dart';
import '../today/today_controller.dart';
import 'plan_status.dart';
import 'planner_widgets.dart';

/// The Qur'an Planner: finish the whole Qur'an by a day the reader chooses.
///
/// Built to be understood at a glance — one question (when do you want to
/// finish?), one number (today's goal), one button (Continue reading).
///
/// A plan keeps its own reading, separate from the Daily Ayah, and balances
/// itself: read more one day and the days after get lighter; read less and
/// what is left is spread over the days that remain. The finish date holds,
/// and nothing is ever marked read on the reader's behalf.
class PlannerScreen extends ConsumerWidget {
  const PlannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ReadingPlan plan = ref.watch(
      userPreferencesProvider.select((prefs) => prefs.plan),
    );
    final TodayState? today = ref.watch(todayControllerProvider).value;
    final AsyncValue<PlanStatus?> status = ref.watch(planStatusProvider);
    final DateTime now = ref.watch(clockProvider)();
    final int total = today?.total ?? 0;

    final List<Widget> body;
    if (today != null && today.edition == null) {
      body = <Widget>[const _NoEditionYet()];
    } else if (plan.isPaced) {
      body = <Widget>[
        status.when(
          // Keeps today's goal on screen while it is worked out again, rather
          // than flashing a spinner after every change.
          skipLoadingOnReload: true,
          data: (PlanStatus? value) =>
              value == null ? const SizedBox.shrink() : _TodayCard(status: value),
          loading: () => const LoadingView(),
          error: (Object error, StackTrace stack) => ErrorStateView(
            message: 'Your plan could not be loaded. Your reading is safe.',
            onRetry: () => ref.invalidate(planStatusProvider),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const OrnateHeading('Your plan'),
        const SizedBox(height: AppSpacing.md),
        _PlanChoices(plan: plan, total: total, now: now),
        const SizedBox(height: AppSpacing.xxl),
        const OrnateHeading('Reminder'),
        const SizedBox(height: AppSpacing.md),
        _PlanReminder(plan: plan),
        const SizedBox(height: AppSpacing.xxl),
        const OrnateHeading('Start over'),
        const SizedBox(height: AppSpacing.md),
        _StartOver(plan: plan, now: now),
      ];
    } else {
      body = <Widget>[
        const _Intro(),
        const SizedBox(height: AppSpacing.xxl),
        const OrnateHeading('Choose your plan'),
        const SizedBox(height: AppSpacing.md),
        _PlanChoices(plan: plan, total: total, now: now),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Your Daily Ayah carries on as before. A plan keeps its own reading '
          'and its own progress, so one never counts towards the other.',
          style: AppTypography.reference.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ];
    }

    return AppPage(
      title: 'Qur’an Planner',
      subtitle: 'Finish the whole Qur’an by a day you choose.',
      showBackButton: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: body,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// With a plan
// ---------------------------------------------------------------------------

/// Today's goal, how the plan is going, and the way into the reading.
class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.status});

  final PlanStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool complete = status.standing == PlanStanding.complete;
    return OrnateCard(
      title: 'Today’s goal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(child: GoalRing(goal: status.goal)),
          const SizedBox(height: AppSpacing.xl),
          PlanStatsRow(status: status),
          const SizedBox(height: AppSpacing.lg),
          PlanStandingNote(status: status),
          const SizedBox(height: AppSpacing.lg),
          if (complete)
            FilledButton.icon(
              onPressed: () => confirmRestartPlan(context, ref),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              icon: const Icon(Icons.replay, size: 20),
              label: const Text('Read the Qur’an again'),
            )
          else
            const ContinueReadingButton(),
        ],
      ),
    );
  }
}

/// The plan's own daily reminder: on or off, and when — as many times a day
/// as the reader wants, up to five.
class _PlanReminder extends ConsumerWidget {
  const _PlanReminder({required this.plan});

  final ReadingPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = context.colors;
    final bool blocked =
        ref.watch(reminderReadinessProvider).value?.isBlocked ?? false;
    final TodayController controller =
        ref.read(todayControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Panel(
          children: <Widget>[
            SettingsRow(
              label: 'Remind me every day',
              description: 'A notification with today’s goal. Tap it to see '
                  'your goal and start reading.',
              trailing: Switch(
                value: plan.reminderEnabled,
                onChanged: (bool on) async {
                  if (on) await askForNotifications(ref);
                  await controller.setPlanReminder(enabled: on);
                },
              ),
            ),
            if (plan.reminderEnabled)
              ...reminderTimeRows(
                context: context,
                times: plan.reminderTimes,
                onChanged: controller.setPlanReminderTimes,
                firstNote: 'Today’s goal.',
                laterNote: 'What is left of it — skipped once it is met.',
              ),
          ],
        ),
        if (plan.reminderEnabled && blocked) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Notifications are turned off for Daily Quran on this phone, so '
            'this reminder cannot arrive.',
            style: AppTypography.reference.copyWith(color: colors.danger),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => ReminderPermissionFlow.openSystemSettings(context),
              child: const Text('Open phone settings'),
            ),
          ),
        ],
      ],
    );
  }

}

/// Plan again from today, start from the first ayah, or stop the plan.
class _StartOver extends ConsumerWidget {
  const _StartOver({required this.plan, required this.now});

  final ReadingPlan plan;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = context.colors;
    final TextStyle note = AppTypography.reference.copyWith(
      color: colors.textSecondary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: () => _replan(context, ref),
          icon: const Icon(Icons.event_repeat, size: 18),
          label: const Text('Plan again from today'),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          plan.kind == ReadingPlanKind.custom
              ? 'Keeps what you have read. Pick a new finish date, and the '
                  'rest is spread from today.'
              : 'Keeps what you have read, and spreads the rest from today. '
                  'Useful after a long break.',
          style: note,
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          onPressed: () => confirmRestartPlan(context, ref),
          icon: const Icon(Icons.replay, size: 18),
          label: const Text('Start from the first ayah'),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Clears your plan’s reading and starts it again from today. Your '
          'Daily Ayah is not affected.',
          style: note,
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          onPressed: () => _confirmStop(context, ref),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.danger,
            side: BorderSide(color: colors.danger.withValues(alpha: 0.55)),
          ),
          icon: const Icon(Icons.close, size: 18),
          label: const Text('Stop my plan'),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Turns the planner off and clears the plan’s reading. Your Daily '
          'Ayah is not affected.',
          style: note,
        ),
      ],
    );
  }

  Future<void> _replan(BuildContext context, WidgetRef ref) async {
    DateTime? target;
    if (plan.kind == ReadingPlanKind.custom) {
      target = await pickFinishDate(context, now: now, current: plan.targetDate);
      if (target == null) return;
    }
    await ref
        .read(todayControllerProvider.notifier)
        .replanFromToday(targetDate: target);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Your plan now runs from today.')),
    );
  }

  Future<void> _confirmStop(BuildContext context, WidgetRef ref) async {
    final bool stop = await _confirm(
      context,
      title: 'Stop your plan?',
      message: 'The planner will turn off and your plan’s reading will be '
          'cleared. Your Daily Ayah stays as it is.',
      action: 'Stop plan',
    );
    if (!stop) return;
    await ref.read(todayControllerProvider.notifier).stopPlan();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Your plan is stopped.')),
    );
  }
}

/// Asks before clearing the plan's reading and starting it over.
Future<void> confirmRestartPlan(BuildContext context, WidgetRef ref) async {
  final bool restart = await _confirm(
    context,
    title: 'Start from the first ayah?',
    message: 'Your plan’s reading will be cleared and the plan will start '
        'again from today. Your Daily Ayah stays as it is.',
    action: 'Start over',
  );
  if (!restart) return;
  await ref.read(todayControllerProvider.notifier).restartPlan();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Your plan starts again from the first ayah.')),
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.danger,
              ),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
}

// ---------------------------------------------------------------------------
// Choosing a plan
// ---------------------------------------------------------------------------

/// The three plans, each described by the day it finishes and the daily goal
/// it works out to for the edition open.
class _PlanChoices extends ConsumerWidget {
  const _PlanChoices({
    required this.plan,
    required this.total,
    required this.now,
  });

  final ReadingPlan plan;
  final int total;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool custom = plan.kind == ReadingPlanKind.custom;
    final UserPreferences preferences = ref.watch(userPreferencesProvider);
    // Timed for what is actually on the reader's screen: the Arabic, the
    // translation, or both — and a second translation when there is one.
    final int pace = ReadingPace.secondsPerAyah(
      preferences.languageMode,
      secondTranslation: preferences.secondaryEditionId != null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ChoiceCard(
          title: PlanLabels.month,
          subtitle: _datedSubtitle(ReadingPlanKind.oneMonth, pace),
          icon: Icons.calendar_view_month,
          selected: plan.kind == ReadingPlanKind.oneMonth,
          onTap: () => _choose(context, ref, ReadingPlanKind.oneMonth),
        ),
        const SizedBox(height: AppSpacing.sm),
        _ChoiceCard(
          title: PlanLabels.year,
          subtitle: _datedSubtitle(ReadingPlanKind.oneYear, pace),
          icon: Icons.calendar_today,
          selected: plan.kind == ReadingPlanKind.oneYear,
          onTap: () => _choose(context, ref, ReadingPlanKind.oneYear),
        ),
        const SizedBox(height: AppSpacing.sm),
        _ChoiceCard(
          title: PlanLabels.custom,
          subtitle: _customSubtitle(pace),
          icon: Icons.edit_calendar_outlined,
          selected: custom,
          // Tapping the chosen-date plan again is how its date is changed.
          actionHint: custom ? 'Change date' : null,
          onTap: () => _chooseDate(context, ref),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Times are a rough guide, at about $pace seconds an ayah — '
          'yours will depend on how you like to read.',
          style: AppTypography.reference.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ],
    );
  }

  /// "Finish by Feb 6, 2026" over "About 202 ayat a day · around 1 h 10 min".
  ///
  /// The plan already running is described as it runs — its own finish date
  /// and rate — while the others say what they would be if chosen today.
  String _datedSubtitle(ReadingPlanKind kind, int pace) {
    final ReadingPlan candidate = plan.kind == kind
        ? plan
        : ReadingPlan(kind: kind, startedOn: now);
    return _describe(candidate, pace);
  }

  String _customSubtitle(int pace) {
    if (plan.kind != ReadingPlanKind.custom || plan.targetDate == null) {
      return 'Choose the day you want to finish.';
    }
    return _describe(plan, pace);
  }

  String _describe(ReadingPlan candidate, int pace) {
    final DateTime start = candidate.startedOn ?? now;
    final DateTime finish = candidate.deadlineFrom(start)!;
    final int? rate = candidate.nominalPerDay(total, today: now);
    final String by = 'Finish by ${Formatting.date(finish)}';
    if (rate == null) return by;
    final int minutes = ReadingPace.minutesFor(rate, secondsPerAyah: pace);
    return '$by\nAbout ${ayatCount(rate)} a day · around '
        '${Encouragement.readingTimeWords(minutes * 60)}';
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    ReadingPlanKind kind,
  ) async {
    if (plan.kind == kind) return;
    await _start(context, ref, ReadingPlan(kind: kind));
  }

  Future<void> _chooseDate(BuildContext context, WidgetRef ref) async {
    final DateTime? picked = await pickFinishDate(
      context,
      now: now,
      current: plan.kind == ReadingPlanKind.custom ? plan.targetDate : null,
    );
    if (picked == null || !context.mounted) return;
    await _start(
      context,
      ref,
      ReadingPlan(kind: ReadingPlanKind.custom, targetDate: picked),
    );
  }

  Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    ReadingPlan next,
  ) async {
    final bool starting = !plan.isPaced;
    // A new plan comes with its reminder on, so the moment it is chosen is the
    // moment asking to send notifications makes sense.
    if (starting && plan.reminderEnabled) await askForNotifications(ref);
    await ref.read(todayControllerProvider.notifier).choosePlan(next);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          starting ? 'Your plan is ready.' : 'Your plan now runs from today.',
        ),
      ),
    );
  }
}

/// Raises the operating system's notification prompt if it has not been
/// answered yes. Only ever called once the reader has asked for a reminder.
Future<void> askForNotifications(WidgetRef ref) async {
  final NotificationScheduler scheduler =
      ref.read(notificationSchedulerProvider);
  final ReminderReadiness readiness = await scheduler.readiness();
  if (!readiness.needs(ReminderRequirement.notifications)) return;
  await scheduler.request(ReminderRequirement.notifications);
  ref.invalidate(reminderReadinessProvider);
}

/// The calendar for choosing the day the Qur'an is finished.
///
/// The earliest offer is tomorrow — today cannot be planned towards — and five
/// years out is far beyond the gentlest plan anyone would keep.
Future<DateTime?> pickFinishDate(
  BuildContext context, {
  required DateTime now,
  DateTime? current,
}) {
  final DateTime first = DateTime(now.year, now.month, now.day + 1);
  final DateTime last = DateTime(now.year + 5, now.month, now.day);
  DateTime initial = current ?? DateTime(now.year, now.month, now.day + 30);
  if (initial.isBefore(first)) initial = first;
  if (initial.isAfter(last)) initial = last;

  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: last,
    helpText: 'Finish the Qur’an by',
    confirmText: 'Set the date',
  );
}

/// One plan, as a card that holds its selection with a quiet accent.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.actionHint,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  /// Shown on a selected card that does something when tapped again.
  final String? actionHint;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: selected ? colors.accentSoft : colors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: selected ? colors.accent : colors.border,
                width: selected ? 1.4 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                ExcludeSemantics(
                  child: Icon(
                    icon,
                    size: 22,
                    color: selected ? colors.accent : colors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: AppTypography.body.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.reference.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      if (selected && actionHint != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          actionHint!,
                          style: AppTypography.reference.copyWith(
                            color: colors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ExcludeSemantics(
                  child: Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    size: 22,
                    color: selected ? colors.accent : colors.border,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Without a plan
// ---------------------------------------------------------------------------

/// What a plan is, in three steps.
class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return OrnateCard(
      title: 'Make a plan',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Want to finish the whole Qur’an? Choose when, and the planner '
            'tells you how much to read each day.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _Step(number: 1, text: 'Choose when you want to finish.'),
          const _Step(number: 2, text: 'Get a small goal for each day.'),
          const _Step(
            number: 3,
            text: 'Read more or less — the goal adjusts itself.',
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.accentSoft,
              border: Border.all(color: colors.warm.withValues(alpha: 0.6)),
            ),
            child: Text(
              '$number',
              style: AppTypography.progressMeta.copyWith(
                color: colors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: AppTypography.body.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nothing to plan until a translation is open.
class _NoEditionYet extends StatelessWidget {
  const _NoEditionYet();

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Icons.menu_book_outlined,
      title: 'Choose a translation first',
      message: 'The planner works out your daily goal from the translation '
          'you read.',
      action: FilledButton(
        onPressed: () => context.go(Routes.library),
        child: const Text('Open the library'),
      ),
    );
  }
}

/// A bordered surface of settings rows, divided by hairlines.
class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.lg),
                child: Divider(height: 1, color: colors.border),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}
