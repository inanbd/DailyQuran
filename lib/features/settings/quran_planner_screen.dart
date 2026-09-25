import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/formatting.dart';
import '../../domain/entities/reading_plan.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/entities/user_preferences.dart';
import '../../domain/services/plan_scheduler.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/ornaments.dart';
import '../today/today_controller.dart';

/// The Qur'an Planner: the whole reading, shaped towards a finishing day.
///
/// Three commitments, made once here and honoured everywhere else:
///
///  * **A date, not a ledger.** A plan is a finishing day — a month out, a
///    year out, or wherever the reader chooses to put it. Each day asks for
///    what is left divided by the days left, so reading more lightens every
///    day that follows and reading less spreads the difference forward. The
///    date holds; no backlog is ever written down.
///  * **Honest numbers.** Every rate on this screen is computed for the
///    edition actually open, by the same arithmetic the scheduler uses — the
///    screen can never advertise a pace the plan will not ask for.
///  * **A way back.** A plan can be measured afresh from today, and a whole
///    reading can begin again from the first ayah, at any time. A deadline
///    without an escape hatch is a trap, not a plan.
class QuranPlannerScreen extends ConsumerWidget {
  const QuranPlannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserPreferences preferences = ref.watch(userPreferencesProvider);
    final TodayState? today = ref.watch(todayControllerProvider).value;
    final ReadingPlan plan = preferences.plan;
    final DateTime now = ref.watch(clockProvider)();
    final int total = today?.total ?? 0;

    return AppPage(
      title: 'Qur’an Planner',
      subtitle: 'The whole reading, shaped to a day of your choosing.',
      showBackButton: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PlannerHero(
            plan: plan,
            portion: today?.portion,
            progress: today?.progress,
            total: total,
            now: now,
          ),
          const SizedBox(height: AppSpacing.xxl),
          const _SectionHeading('Your pace'),
          const SizedBox(height: AppSpacing.md),
          _PaceChoices(plan: plan, total: total, now: now),
          const SizedBox(height: AppSpacing.lg),
          Text(
            plan.isPaced
                ? 'The plan balances itself around you. Read generously one '
                    'day and every day after it grows lighter; miss a few and '
                    'what remains is spread over the days left — the '
                    'finishing day holds either way, and nothing is ever '
                    'marked read for you.'
                : 'One ayah each time you sit down to read, for as long as it '
                    'takes. Nothing to fall behind on.',
            style: AppTypography.reference.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          const _SectionHeading('Begin anew'),
          const SizedBox(height: AppSpacing.md),
          _BeginAnew(plan: plan, hasEdition: today?.edition != null, now: now),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The hero card
// ---------------------------------------------------------------------------

/// Where the journey stands: the ring of the whole reading, today's portion,
/// the days that remain, and the day it is all working towards.
class _PlannerHero extends StatelessWidget {
  const _PlannerHero({
    required this.plan,
    required this.portion,
    required this.progress,
    required this.total,
    required this.now,
  });

  final ReadingPlan plan;
  final ReadingPortion? portion;
  final ReadingProgress? progress;
  final int total;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final Color hairline = colors.warm.withValues(alpha: 0.55);

    final Widget body = total <= 0 || progress == null
        ? _emptyBody(colors)
        : _journeyBody(context, colors);

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
            Text(
              'THE KHATMAH JOURNEY',
              textAlign: TextAlign.center,
              style: AppTypography.overline.copyWith(
                color: colors.textSecondary,
                letterSpacing: 2.4,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            body,
            const SizedBox(height: AppSpacing.md),
            OrnamentalDivider(color: hairline, starSize: 7),
          ],
        ),
      ),
    );
  }

  /// Nothing open to plan yet — said plainly instead of a card of zeroes.
  Widget _emptyBody(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Text(
        'Choose a translation in the library and the planner will shape '
        'itself around the edition you read.',
        textAlign: TextAlign.center,
        style: AppTypography.body.copyWith(color: colors.textSecondary),
      ),
    );
  }

  Widget _journeyBody(BuildContext context, AppColors colors) {
    final ReadingProgress reading = progress!;
    final bool complete = reading.totalRead >= total;
    final double fraction =
        (reading.totalRead / total).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: ProgressRing(
            progress: fraction,
            size: 148,
            strokeWidth: 9,
            trackColor: colors.accentSoft,
            fillColor: colors.accent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  Formatting.percent(fraction * 100),
                  style: AppTypography.statNumeral.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${Formatting.count(reading.totalRead)} of '
                  '${Formatting.count(total)}',
                  style: AppTypography.progressMeta.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (!complete) ...<Widget>[
          _stats(colors),
          const SizedBox(height: AppSpacing.lg),
        ],
        Text(
          complete
              ? 'The reading is complete — Alhamdulillah. Begin anew below '
                  'whenever you are ready.'
              : _statusSentence(),
          textAlign: TextAlign.center,
          style: AppTypography.reference.copyWith(
            color: (portion?.periodsBehind ?? 0) > 0 && !complete
                ? colors.textPrimary
                : colors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _stats(AppColors colors) {
    final ReadingPortion? current = portion;
    final DateTime? deadline = current?.deadline;

    final List<Widget> cells;
    if (plan.isPaced && current != null && deadline != null) {
      cells = <Widget>[
        _HeroStat(
          value: Formatting.count(current.target),
          label: current.target == 1 ? 'ayah today' : 'ayat today',
        ),
        _HeroStat(
          value: Formatting.count(_daysLeft(deadline)),
          label: 'days left',
        ),
        _HeroStat(value: Formatting.date(deadline), label: 'finish by'),
      ];
    } else {
      final int remaining = (total - progress!.totalRead).clamp(0, total);
      cells = <Widget>[
        const _HeroStat(value: '1', label: 'ayah today'),
        _HeroStat(
          value: Formatting.count(remaining),
          label: 'ayat remain',
        ),
        const _HeroStat(value: 'Open', label: 'no end date'),
      ];
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < cells.length; i++) ...<Widget>[
            if (i > 0)
              VerticalDivider(
                width: 1,
                thickness: 1,
                indent: 6,
                endIndent: 6,
                color: colors.border,
              ),
            Expanded(child: cells[i]),
          ],
        ],
      ),
    );
  }

  String _statusSentence() {
    final ReadingPortion? current = portion;
    if (!plan.isPaced || current == null || current.deadline == null) {
      return 'The unhurried path — one ayah at a time, no date to keep.';
    }

    final DateTime deadline = current.deadline!;
    final DateTime? projected = current.projectedCompletion;
    if (projected != null && projected != deadline) {
      // Only ever true once the date has actually gone: the plan has stopped
      // chasing it and says when it will really finish instead.
      return 'That date has passed. At this pace the reading finishes around '
          '${Formatting.date(projected)}.';
    }
    if (current.periodsBehind > 0) {
      return 'About ${Formatting.count(current.periodsBehind)} '
          '${current.periodsBehind == 1 ? 'reading' : 'readings'} behind — '
          '${Formatting.count(current.target)} a day from here still reaches '
          '${Formatting.date(deadline)}.';
    }
    if (current.isAhead) {
      return 'Ahead of pace — ${Formatting.count(current.target)} a day from '
          'here reaches ${Formatting.date(deadline)}.';
    }
    return 'On course for ${Formatting.date(deadline)}, at '
        '${Formatting.count(current.target)} a day.';
  }

  /// Reading days remaining, today included. Counted in UTC epoch days so a
  /// DST shift can never lose or invent one.
  int _daysLeft(DateTime deadline) {
    final int days = _epochDay(deadline) - _epochDay(now) + 1;
    return days < 0 ? 0 : days;
  }

  static int _epochDay(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day).millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay;
}

/// One figure with its caption beneath, centred in its column.
class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          value,
          textAlign: TextAlign.center,
          style: AppTypography.sectionTitle.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.progressMeta.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pace choices
// ---------------------------------------------------------------------------

/// The four paces, each described by the day it finishes on and the daily
/// rate it truly works out to for the edition open.
class _PaceChoices extends ConsumerWidget {
  const _PaceChoices({required this.plan, required this.total, required this.now});

  final ReadingPlan plan;
  final int total;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PaceCard(
          title: 'In a month',
          subtitle: _datedSubtitle(ReadingPlanKind.oneMonth),
          selected: plan.kind == ReadingPlanKind.oneMonth,
          onTap: () => _chooseDated(ref, ReadingPlanKind.oneMonth),
        ),
        const SizedBox(height: AppSpacing.sm),
        _PaceCard(
          title: 'In a year',
          subtitle: _datedSubtitle(ReadingPlanKind.oneYear),
          selected: plan.kind == ReadingPlanKind.oneYear,
          onTap: () => _chooseDated(ref, ReadingPlanKind.oneYear),
        ),
        const SizedBox(height: AppSpacing.sm),
        _PaceCard(
          title: 'By a chosen date',
          subtitle: _customSubtitle(),
          selected: plan.kind == ReadingPlanKind.custom,
          // Tapping the chosen-date plan again is how its date is changed, so
          // the card stays live once selected.
          onTap: () => _chooseCustom(context, ref),
          trailing: plan.kind == ReadingPlanKind.custom
              ? Icon(
                  Icons.edit_calendar_outlined,
                  size: 20,
                  color: context.colors.accent,
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        _PaceCard(
          title: 'One ayah a day',
          subtitle: 'The unhurried pace. No date to keep.',
          selected: plan.kind == ReadingPlanKind.oneAyah,
          onTap: () => _chooseDated(ref, ReadingPlanKind.oneAyah),
        ),
      ],
    );
  }

  /// "By Feb 6, 2026 · about 202 ayat a day" — the date it would finish on if
  /// chosen today, and the rate the plan will actually ask for.
  String _datedSubtitle(ReadingPlanKind kind) {
    final ReadingPlan candidate = ReadingPlan(kind: kind, startedOn: now);
    final DateTime deadline = candidate.deadlineFrom(now)!;
    final int? rate = candidate.nominalPerDay(total, today: now);
    if (rate == null) {
      return kind == ReadingPlanKind.oneMonth
          ? 'The whole Qur’an in thirty days.'
          : 'The whole Qur’an in a year.';
    }
    return 'By ${Formatting.date(deadline)} · ${_aDay(rate)}';
  }

  String _customSubtitle() {
    final DateTime? target =
        plan.kind == ReadingPlanKind.custom ? plan.targetDate : null;
    if (target == null) return 'Finish by a date of your own choosing.';
    final int? rate = plan.nominalPerDay(total, today: now);
    if (rate == null) return 'By ${Formatting.date(target)}';
    return 'By ${Formatting.date(target)} · ${_aDay(rate)}';
  }

  static String _aDay(int rate) =>
      'about ${Formatting.count(rate)} ${rate == 1 ? 'ayah' : 'ayat'} a day';

  Future<void> _chooseDated(WidgetRef ref, ReadingPlanKind kind) async {
    if (plan.kind == kind) return;
    await _apply(
      ref,
      ReadingPlan(
        kind: kind,
        // A plan working towards a date starts its clock the moment it is
        // chosen; one that sets a rate has no clock to start.
        startedOn: kind.isPaced ? ref.read(clockProvider)() : null,
      ),
    );
  }

  Future<void> _chooseCustom(BuildContext context, WidgetRef ref) async {
    final DateTime? picked = await pickFinishDate(
      context,
      now: now,
      current: plan.kind == ReadingPlanKind.custom ? plan.targetDate : null,
    );
    if (picked == null) return;
    await _apply(
      ref,
      ReadingPlan(
        kind: ReadingPlanKind.custom,
        startedOn: ref.read(clockProvider)(),
        targetDate: picked,
      ),
    );
  }

  static Future<void> _apply(WidgetRef ref, ReadingPlan next) async {
    final UserPreferencesController preferences =
        ref.read(userPreferencesProvider.notifier);
    await preferences.update(
      ref.read(userPreferencesProvider).copyWith(plan: next),
    );
    // A reminder counts out the portion, so what is already armed is now
    // describing the old plan.
    await ref.read(notificationPreferencesProvider.notifier).applyToScheduler();
  }
}

/// The calendar for choosing the day a khatmah completes.
///
/// Yesterday cannot be committed to, so the earliest offer is tomorrow; five
/// years out is far beyond the gentlest plan anyone would sustain.
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

/// One pace, presented as a card that holds its selection with a quiet accent
/// rather than a radio dot.
class _PaceCard extends StatelessWidget {
  const _PaceCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

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
                EightPointStar(
                  size: 13,
                  color: selected ? colors.warm : colors.border,
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
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (trailing != null)
                  trailing!
                else
                  ExcludeSemantics(
                    child: Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      size: 20,
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
// Beginning anew
// ---------------------------------------------------------------------------

/// The two ways back: measure the plan afresh from today, or begin the whole
/// reading again from the first ayah.
class _BeginAnew extends ConsumerWidget {
  const _BeginAnew({
    required this.plan,
    required this.hasEdition,
    required this.now,
  });

  final ReadingPlan plan;
  final bool hasEdition;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (plan.isPaced) ...<Widget>[
          OutlinedButton.icon(
            onPressed: () => _replan(context, ref),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Replan from today'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            plan.kind == ReadingPlanKind.custom
                ? 'Keeps everything you have read and lets you choose a new '
                    'finishing date, measured from today.'
                : 'Keeps everything you have read and moves the finishing '
                    'date, so a long gap does not leave you with an '
                    'impossible portion.',
            style: AppTypography.reference.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        OutlinedButton.icon(
          onPressed: hasEdition ? () => _confirmRestart(context, ref) : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.danger,
            side: BorderSide(
              color: hasEdition
                  ? colors.danger.withValues(alpha: 0.55)
                  : colors.border,
            ),
          ),
          icon: const Icon(Icons.replay, size: 18),
          label: const Text('Restart from the beginning'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Marks every ayah unread and begins the reading — and the plan — '
          'anew from the first ayah. Favourites are kept.',
          style: AppTypography.reference.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }

  /// Starts the plan's clock again from today, keeping every ayah read.
  ///
  /// The escape hatch a deadline needs: someone who put the reading down for
  /// two months can pick it up again without being handed a portion no one
  /// could read. A chosen-date plan is asked for its new date, because
  /// re-measuring towards the old one is rarely what a fresh start means.
  Future<void> _replan(BuildContext context, WidgetRef ref) async {
    ReadingPlan next = plan.copyWith(startedOn: ref.read(clockProvider)());
    if (plan.kind == ReadingPlanKind.custom) {
      final DateTime? picked = await pickFinishDate(
        context,
        now: now,
        current: plan.targetDate,
      );
      if (picked == null) return;
      next = next.copyWith(targetDate: picked);
    }

    final UserPreferences preferences = ref.read(userPreferencesProvider);
    await ref
        .read(userPreferencesProvider.notifier)
        .update(preferences.copyWith(plan: next));
    await ref.read(notificationPreferencesProvider.notifier).applyToScheduler();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The plan now runs from today.')),
    );
  }

  Future<void> _confirmRestart(BuildContext context, WidgetRef ref) async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Begin the Qur’an anew?'),
            content: const Text(
              'Every ayah will be marked unread and your plan will start '
              'again from today. This cannot be undone.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep my reading'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.danger,
                ),
                child: const Text('Restart'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    await ref.read(todayControllerProvider.notifier).restart();
    await ref.read(notificationPreferencesProvider.notifier).applyToScheduler();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('The reading begins anew from the first ayah.'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section chrome
// ---------------------------------------------------------------------------

/// A small-caps heading led by a gold star, trailed by a fading hairline.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title);

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
