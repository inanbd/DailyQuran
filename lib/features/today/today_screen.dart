import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/edition_providers.dart';
import '../../app/favourites_providers.dart';
import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/speech_providers.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/formatting.dart';
import '../../domain/entities/ayah.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/entities/reading_track.dart';
import '../../domain/entities/user_preferences.dart';
import '../../domain/services/plan_scheduler.dart';
import '../activity/activity_widgets.dart';
import '../activity/reading_timer.dart';
import '../planner/planner_widgets.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/ayah_view.dart';
import '../../shared/widgets/notice_banner.dart';
import '../../shared/widgets/progress_bar.dart';
import '../../shared/widgets/state_views.dart';
import 'editions_sheet.dart';
import 'scroll_reading.dart';
import 'surahs_sheet.dart';
import 'today_controller.dart';

/// The default screen: today's ayah, and almost nothing else.
///
/// Owns one behaviour beyond rendering: an ayah the reader has actually read
/// marks itself. See [_considerAutoMark].
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  /// How long the end of the ayah has to stay on screen before it counts as
  /// read.
  ///
  /// Long enough that scrolling to the bottom on the way to *Next* does not
  /// mark anything, short enough that someone who has genuinely finished
  /// reading never has to press a button.
  static const Duration dwell = Duration(seconds: 5);

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  /// Sits at the end of the ayah. Auto-marking waits for it to come into view,
  /// which is what "read the whole thing" means.
  final GlobalKey _endOfAyah = GlobalKey();

  Timer? _dwell;

  /// The ayah the running timer belongs to, so a timer armed for one ayah can
  /// never mark a different one.
  String? _armedFor;

  /// Ayat already marked this way. Marking happens once per ayah and never
  /// again: a reader who deliberately marks one back as unread has overruled
  /// us, and must not be fought over it.
  final Set<String> _autoMarked = <String>{};

  @override
  void dispose() {
    _dwell?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<TodayState> state = ref.watch(todayControllerProvider);
    final UserPreferences preferences = ref.watch(userPreferencesProvider);

    // Moving to another ayah retires a timer armed for the last one.
    final String? ayahId = state.value?.ayah?.id;
    if (_armedFor != null && _armedFor != ayahId) {
      _dwell?.cancel();
      _dwell = null;
      _armedFor = null;
    }

    // A short ayah that fits without scrolling is fully read the moment it
    // appears, and produces no scroll notification to say so.
    WidgetsBinding.instance.addPostFrameCallback((_) => _considerAutoMark());

    // Time counts towards the reader's reading time only while there is an
    // ayah on screen to read — not over an error, and not over the finished
    // Qur'an.
    final bool reading =
        state.value?.ayah != null && !(state.value?.isComplete ?? false);

    return ReadingTimer(
      active: reading,
      child: NotificationListener<ScrollNotification>(
        // An ancestor of the page's scroll view, which is the only place these
        // notifications can be caught from.
        onNotification: (ScrollNotification notification) {
          _considerAutoMark();
          // Never absorb it: the scroll view's own listeners still need it.
          return false;
        },
        child: AppPage(
          title: 'Today’s Ayah',
          // With a plan there are two readings, and the top of the page is
          // where the reader picks between them — the choice names the page
          // better than a title could. Read from preferences rather than the
          // loaded state, so it is there from the first frame.
          heading: preferences.plan.isPaced
              ? _TrackSwitch(track: preferences.activeTrack)
              : null,
          actions: <Widget>[
            _SurahsButton(editionId: state.value?.edition?.id),
          ],
          // The body lays itself out: the pages of the carousel slide in from
          // the very edge, and the scrolling view scrolls on its own.
          scrollable: false,
          fullBleed: true,
          child: state.when(
            // Keeps a reading on screen while it reloads — a new translation,
            // a setting changed elsewhere — rather than blanking the carousel.
            // With nothing yet to keep, as right after onboarding, the reader
            // is shown it is loading.
            skipLoadingOnReload: state.value?.hasEdition ?? false,
            loading: () => const _Padded(child: LoadingView()),
            error: (Object error, StackTrace stack) =>
                _Padded(child: _TodayError(error: error)),
            data: (TodayState value) => _TodayBody(
              state: value,
              layout: preferences.readingLayout,
              endOfAyahKey: _endOfAyah,
            ),
          ),
        ),
      ),
    );
  }

  /// Starts the dwell timer once the reader has reached the end of an unread
  /// ayah.
  ///
  /// Deliberately not cancelled by scrolling back up: having reached the end
  /// and stayed is the signal, and re-reading a passage is not a reason to
  /// withdraw it.
  void _considerAutoMark() {
    if (!mounted) return;
    // The scrolling view keeps its own count of what has been read.
    if (ref.read(userPreferencesProvider).readingLayout != ReadingLayout.swipe) {
      return;
    }

    final TodayState? current = ref.read(todayControllerProvider).value;
    final Ayah? ayah = current?.ayah;
    if (ayah == null || current!.isRead) return;
    if (_autoMarked.contains(ayah.id)) return;
    if (_armedFor == ayah.id) return;
    if (!_hasReachedEnd()) return;

    // The page can move on before a rebuild retires the last ayah's timer —
    // a swipe lands between frames — so it is retired here too, rather than
    // left running with nothing to cancel it.
    _dwell?.cancel();
    _armedFor = ayah.id;
    _dwell = Timer(TodayScreen.dwell, () => _markRead(ayah.id));
  }

  /// Whether the end of the ayah has scrolled into the viewport.
  bool _hasReachedEnd() {
    final BuildContext? marker = _endOfAyah.currentContext;
    if (marker == null) return false;
    final RenderObject? object = marker.findRenderObject();
    if (object is! RenderBox || !object.hasSize) return false;
    return object.localToGlobal(Offset.zero).dy <=
        MediaQuery.sizeOf(context).height;
  }

  void _markRead(String ayahId) {
    if (!mounted) return;
    _armedFor = null;

    // The reader may have moved on, or marked it read themselves, in the
    // seconds the timer was running.
    final TodayState? current = ref.read(todayControllerProvider).value;
    if (current?.ayah?.id != ayahId || current!.isRead) return;

    _autoMarked.add(ayahId);
    // Marks without turning the page: a dwell timer that also advanced would
    // walk itself through a whole portion while the reader sat still.
    ref.read(todayControllerProvider.notifier).markReadInPlace();
  }
}

/// A way into the surah index.
///
/// Absent entirely when it would do nothing — no edition open, or none loaded
/// yet — rather than present and inert.
class _SurahsButton extends ConsumerWidget {
  const _SurahsButton({required this.editionId});

  final String? editionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? id = editionId;
    if (id == null) return const SizedBox.shrink();

    final bool hasSurahs =
        ref.watch(surahsProvider(id)).value?.isNotEmpty ?? false;
    if (!hasSurahs) return const SizedBox.shrink();

    return IconButton(
      onPressed: () => SurahsSheet.open(context, id),
      icon: Icon(
        Icons.list_alt_outlined,
        size: 22,
        color: context.colors.textSecondary,
      ),
      tooltip: 'Surahs',
      constraints: const BoxConstraints(
        minWidth: AppSpacing.minTapTarget,
        minHeight: AppSpacing.minTapTarget,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// A body that is not a page of the reading — loading, an error, the finished
/// Qur'an — laid out the way any other screen's is.
class _Padded extends StatelessWidget {
  const _Padded({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: ReadingColumn(
        child: Padding(padding: appPageBodyPadding, child: child),
      ),
    );
  }
}

/// Everything the Read tab can show once it has loaded: nothing chosen yet,
/// the finished Qur'an, or the reading itself, one ayah at a time or as one
/// continuous column.
class _TodayBody extends ConsumerWidget {
  const _TodayBody({
    required this.state,
    required this.layout,
    required this.endOfAyahKey,
  });

  final TodayState state;
  final ReadingLayout layout;

  /// Attached to the end of the ayah on screen, so the screen above can tell
  /// when the reader has scrolled all the way through it.
  final Key endOfAyahKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final QuranEdition? edition = state.edition;
    if (edition == null) return const _Padded(child: _NoEditionChosen());

    if (state.isComplete) {
      return _Padded(
        child: CompletionView(
          edition: edition,
          progress: state.progress!,
          isPlan: state.isPlan,
          onReadAgain: () =>
              ref.read(todayControllerProvider.notifier).restart(),
          onChooseAnother: () => context.go(Routes.library),
        ),
      );
    }

    if (state.ayah == null) {
      return _Padded(
        child: ErrorStateView(
          title: 'This ayah could not be loaded',
          message:
              'The text for position ${state.ordinal} is missing from local '
              'storage. Reinstalling the edition usually fixes this.',
          onRetry: () => ref.read(todayControllerProvider.notifier).refresh(),
        ),
      );
    }

    final UserPreferences preferences = ref.watch(userPreferencesProvider);
    if (layout == ReadingLayout.scroll) {
      return ScrollReading(
        // A new column whenever what it shows changes shape — another
        // translation, another reading, text of another size — opened afresh
        // at the reader's place rather than left at an offset that now points
        // somewhere else.
        key: ValueKey<String>(<Object?>[
          state.scope,
          edition.id,
          state.secondaryEdition?.id,
          preferences.languageMode,
          preferences.textSize,
          preferences.showWordByWord,
          preferences.showTransliteration,
        ].join('|')),
        state: state,
      );
    }

    return _PagedReading(
      // Another reading, or an edition of another length, is another set of
      // pages; a new translation of the same ayat keeps the carousel as it is.
      key: ValueKey<String>('${state.scope}|${state.total}'),
      state: state,
      endOfAyahKey: endOfAyahKey,
    );
  }
}

/// The ayat as the pages of a carousel: each slides in from the edge beneath
/// the reader's finger, the next one already there to be revealed, the way a
/// gallery of pictures turns — left carries the reader forward, right back.
///
/// Turning the page is browsing, not reading, as it always was: a page that
/// comes to rest becomes the reader's place and nothing on the way is marked.
/// The arrows, *Mark as read* carrying on to the next ayah, and a jump from the
/// surah index all slide the carousel the same way a finger does.
class _PagedReading extends ConsumerStatefulWidget {
  const _PagedReading({
    required this.state,
    required this.endOfAyahKey,
    super.key,
  });

  final TodayState state;
  final Key endOfAyahKey;

  /// How long a page takes to slide into place when the app turns it.
  static const Duration turn = Duration(milliseconds: 320);

  @override
  ConsumerState<_PagedReading> createState() => _PagedReadingState();
}

class _PagedReadingState extends ConsumerState<_PagedReading> {
  late final PageController _pages =
      PageController(initialPage: widget.state.ordinal - 1);

  /// The position a swipe has asked the controller for and the page does not
  /// yet show. Until it does, the carousel does not chase the place the page
  /// had before — which would slide it straight back under the reader's
  /// finger.
  int? _awaiting;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_PagedReading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.ordinal != widget.state.ordinal) {
      // After this frame: a page cannot be moved while it is being built.
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
    }
  }

  /// Brings the carousel to the reader's place when something other than a
  /// swipe moved it: the next ayah after *Mark as read*, the surah index, a
  /// new day's reading.
  void _follow() {
    if (!mounted || !_pages.hasClients || _awaiting != null) return;
    // Never pulled out from under a finger that is still on it.
    if (_pages.position.isScrollingNotifier.value) return;
    final int target = widget.state.ordinal - 1;
    final int shown = (_pages.page ?? target.toDouble()).round();
    if (shown == target) return;
    if ((shown - target).abs() == 1) {
      _pages.animateToPage(
        target,
        duration: _PagedReading.turn,
        curve: Curves.easeOutCubic,
      );
    } else {
      // Further than a page: a slide through everything in between would be
      // a blur, and the place is the point.
      _pages.jumpToPage(target);
    }
  }

  /// Makes the page the carousel came to rest on the reader's place.
  bool _onScroll(ScrollNotification notification) {
    // Only the carousel's own sideways movement, not an ayah being scrolled
    // through inside a page.
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.horizontal ||
        notification is! ScrollEndNotification) {
      return false;
    }
    final int ordinal = (_pages.page ?? 0).round() + 1;
    if (ordinal != widget.state.ordinal) unawaited(_settleOn(ordinal));
    return false;
  }

  Future<void> _settleOn(int ordinal) async {
    _awaiting = ordinal;
    await ref.read(todayControllerProvider.notifier).goTo(ordinal);
    if (_awaiting != ordinal) return;
    _awaiting = null;
    // Something else may have moved the place in the meantime.
    if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
  }

  /// Slides to [ordinal], as the arrows do.
  void _turnTo(int ordinal) {
    if (!_pages.hasClients) return;
    _pages.animateToPage(
      ordinal - 1,
      duration: _PagedReading.turn,
      curve: Curves.easeOutCubic,
    );
  }

  /// Makes [ordinal] the reader's place first, when a page still sliding in
  /// is acted on, so what is done is done to the ayah on that page.
  Future<void> _onPage(int ordinal, Future<void> Function() action) async {
    if (ordinal != widget.state.ordinal) await _settleOn(ordinal);
    await action();
  }

  @override
  Widget build(BuildContext context) {
    final TodayState state = widget.state;
    final TodayController controller =
        ref.read(todayControllerProvider.notifier);

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: PageView.builder(
        controller: _pages,
        itemCount: state.total,
        // The pages either side stay built, so a swipe reveals an ayah that is
        // already there rather than one still loading.
        allowImplicitScrolling: true,
        itemBuilder: (BuildContext context, int index) {
          final int ordinal = index + 1;
          return _AyahPage(
            state: state,
            ordinal: ordinal,
            endOfAyahKey:
                ordinal == state.ordinal ? widget.endOfAyahKey : null,
            onPrevious: ordinal > 1 ? () => _turnTo(ordinal - 1) : null,
            onNext: ordinal < state.total ? () => _turnTo(ordinal + 1) : null,
            onMarkRead: () => _onPage(ordinal, controller.markRead),
            onMarkUnread: () => _onPage(ordinal, controller.markUnread),
          );
        },
      ),
    );
  }
}

/// One page of the carousel: an ayah with its place in the Qur'an, how the
/// reading is going, and the controls to read on.
///
/// The page the reader's place is on is drawn from the controller's state;
/// the pages either side, which a swipe shows before it comes to rest, load
/// their own ayah.
class _AyahPage extends ConsumerWidget {
  const _AyahPage({
    required this.state,
    required this.ordinal,
    required this.endOfAyahKey,
    required this.onPrevious,
    required this.onNext,
    required this.onMarkRead,
    required this.onMarkUnread,
  });

  final TodayState state;
  final int ordinal;
  final Key? endOfAyahKey;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onMarkRead;
  final VoidCallback onMarkUnread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final QuranEdition edition = state.edition!;

    final Ayah? ayah;
    final Ayah? secondaryAyah;
    final bool isRead;
    if (ordinal == state.ordinal) {
      ayah = state.ayah;
      secondaryAyah = state.secondaryAyah;
      isRead = state.isRead;
    } else {
      final ReadingPage? page = ref
          .watch(
            readingPageProvider((
              editionId: edition.id,
              secondaryId: state.secondaryEdition?.id,
              scope: state.scope!,
              ordinal: ordinal,
            )),
          )
          .value;
      ayah = page?.ayah;
      secondaryAyah = page?.secondaryAyah;
      isRead = page?.isRead ?? false;
    }

    return SingleChildScrollView(
      child: ReadingColumn(
        child: Padding(
          padding: appPageBodyPadding,
          child: ayah == null
              // A page still loading keeps its shape, so nothing jumps when
              // its ayah arrives.
              ? const SizedBox(height: 320)
              : _AyahPageBody(
                  state: state,
                  edition: edition,
                  ayah: ayah,
                  secondaryAyah: secondaryAyah,
                  isRead: isRead,
                  endOfAyahKey: endOfAyahKey,
                  onPrevious: onPrevious,
                  onNext: onNext,
                  onMarkRead: onMarkRead,
                  onMarkUnread: onMarkUnread,
                ),
        ),
      ),
    );
  }
}

class _AyahPageBody extends ConsumerWidget {
  const _AyahPageBody({
    required this.state,
    required this.edition,
    required this.ayah,
    required this.secondaryAyah,
    required this.isRead,
    required this.endOfAyahKey,
    required this.onPrevious,
    required this.onNext,
    required this.onMarkRead,
    required this.onMarkUnread,
  });

  final TodayState state;
  final QuranEdition edition;
  final Ayah ayah;
  final Ayah? secondaryAyah;
  final bool isRead;
  final Key? endOfAyahKey;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onMarkRead;
  final VoidCallback onMarkUnread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserPreferences preferences = ref.watch(userPreferencesProvider);
    final SpokenUtterance? speaking = ref.watch(speechControllerProvider);
    // A device with no voice for this translation's language gets no play
    // button at all, rather than one that would silently do nothing.
    final bool canSpeak =
        ref.watch(speechAvailableProvider(edition.languageCode)).value ?? false;
    final bool isFavourite = ref.watch(isFavouriteProvider(ayah)).value ?? false;
    final ReadingProgress progress = state.progress!;
    final QuranEdition? second = state.secondaryEdition;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _AyahMeta(edition: edition, ayah: ayah),
        if (edition.isFixture) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          const NoticeBanner(
            tone: NoticeTone.warning,
            title: 'Development data',
            message:
                'This is placeholder text for building and testing the app — '
                'not the Qur’an. Import a verified edition to read real '
                'content.',
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        AyahView(
          key: ValueKey<String>(ayah.id),
          ayah: ayah,
          languageMode: preferences.languageMode,
          textScale: preferences.textSize.scale,
          showTransliteration: preferences.showTransliteration,
          showWordByWord: preferences.showWordByWord,
          translationIsRightToLeft: edition.isRightToLeft,
          // One ayah to a page, so the citation below it only repeats what the
          // page already says.
          showReference: false,
          secondaryTranslation:
              second != null && (secondaryAyah?.hasTranslation ?? false)
                  ? SecondaryTranslation(
                      text: secondaryAyah!.translationText!,
                      title: second.titleEnglish,
                      isRightToLeft: second.isRightToLeft,
                    )
                  : null,
          onSpeakTranslation: canSpeak
              ? () => ref.read(speechControllerProvider.notifier).toggle(
                    ayah.id,
                    ayah.translationText ?? '',
                    languageCode: edition.languageCode,
                  )
              : null,
          isSpeakingTranslation: speaking ==
              SpokenUtterance(
                ayahId: ayah.id,
                languageCode: edition.languageCode,
              ),
          isFavourite: isFavourite,
          onToggleFavourite: () =>
              ref.read(favouritesControllerProvider.notifier).toggle(ayah),
        ),
        // Nothing to look at: the point past which the whole ayah, citation
        // included, has been on screen.
        SizedBox(key: endOfAyahKey, height: AppSpacing.xxl),
        if (state.isPlan && state.portion != null) ...<Widget>[
          _GoalCard(portion: state.portion!),
          const SizedBox(height: AppSpacing.lg),
        ],
        ReadingProgressBar(
          read: progress.totalRead,
          total: progress.totalAyah,
        ),
        const ReadingTimeGoalBar(),
        const SizedBox(height: AppSpacing.xl),
        _ReadingActions(
          isRead: isRead,
          onPrevious: onPrevious,
          onNext: onNext,
          onMarkRead: onMarkRead,
          onMarkUnread: onMarkUnread,
        ),
      ],
    );
  }
}

/// Chooses between the plan's reading and the Daily Ayah — the plan first,
/// since a reader who made one reads it first.
///
/// Sits where the page title would, so the reader never has to wonder which
/// reading the page is showing.
class _TrackSwitch extends ConsumerWidget {
  const _TrackSwitch({required this.track});

  final ReadingTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = context.colors;
    Color pick(Set<WidgetState> states, Color on, Color off) =>
        states.contains(WidgetState.selected) ? on : off;

    return SegmentedButton<ReadingTrack>(
      segments: const <ButtonSegment<ReadingTrack>>[
        ButtonSegment<ReadingTrack>(
          value: ReadingTrack.plan,
          label: Text('My Plan'),
          icon: Icon(Icons.flag_outlined, size: 18),
        ),
        ButtonSegment<ReadingTrack>(
          value: ReadingTrack.daily,
          label: Text('Daily Ayah'),
          icon: Icon(Icons.wb_sunny_outlined, size: 18),
        ),
      ],
      selected: <ReadingTrack>{track},
      showSelectedIcon: false,
      expandedInsets: EdgeInsets.zero,
      onSelectionChanged: (Set<ReadingTrack> chosen) => ref
          .read(todayControllerProvider.notifier)
          .switchTrack(chosen.first),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) =>
              pick(states, colors.accentSoft, colors.surface),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) =>
              pick(states, colors.accent, colors.textSecondary),
        ),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: colors.border),
        ),
        textStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(
            fontFamily: AppFonts.english,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        minimumSize: const WidgetStatePropertyAll<Size>(
          Size.fromHeight(AppSpacing.minTapTarget),
        ),
      ),
    );
  }
}

/// Today's goal on the plan's reading: how much is read, and — when the goal
/// has grown or shrunk — the plain reason why.
class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.portion});

  final ReadingPortion portion;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final String? why = portion.isComplete
        ? null
        : portion.isCatchingUp
            ? 'You missed some reading, so today’s goal is a little bigger.'
            : portion.isAhead
                ? 'You read extra before, so today’s goal is smaller.'
                : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.warm.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Today’s goal',
                  style: AppTypography.sectionTitle.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.go(Routes.planner),
                child: const Text('Planner'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ReadingProgressBar(
              read: portion.read,
              total: portion.target,
              label: portion.isComplete
                  ? 'Today’s goal is done'
                  : portion.progressWords,
            ),
          ),
          if (why != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Text(
                why,
                style: AppTypography.reference.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Saheeh International" over "Al-Baqarah · 2:255 · Juz' 3".
class _AyahMeta extends StatelessWidget {
  const _AyahMeta({required this.edition, required this.ayah});

  final QuranEdition edition;
  final Ayah ayah;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final List<String> parts = <String>[
      if (ayah.surahNameEnglish != null) ayah.surahNameEnglish!,
      ayah.verseKey,
      if (ayah.juz != null) 'Juz’ ${ayah.juz}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Tapping the translation's name is how it is changed, which puts
        // the control next to the thing it names rather than in a menu.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: EditionSwitcher(edition: edition),
        ),
        Text(
          parts.join(' · '),
          style: AppTypography.metadata.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// Previous · Mark as read · Next.
///
/// The arrows turn the page the way a swipe does, so they are handed in by
/// the carousel rather than moving the reading behind its back.
class _ReadingActions extends StatelessWidget {
  const _ReadingActions({
    required this.isRead,
    required this.onPrevious,
    required this.onNext,
    required this.onMarkRead,
    required this.onMarkUnread,
  });

  final bool isRead;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onMarkRead;
  final VoidCallback onMarkUnread;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;

    return Row(
      children: <Widget>[
        _NavButton(
          icon: Icons.chevron_left,
          tooltip: 'Previous ayah',
          onPressed: onPrevious,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: isRead
              ? OutlinedButton.icon(
                  onPressed: onMarkUnread,
                  icon: Icon(Icons.check, size: 18, color: colors.accent),
                  label: const Text('Read'),
                )
              : FilledButton(
                  onPressed: onMarkRead,
                  child: const Text('Mark as read'),
                ),
        ),
        const SizedBox(width: AppSpacing.md),
        _NavButton(
          icon: Icons.chevron_right,
          tooltip: 'Next ayah',
          onPressed: onNext,
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return SizedBox(
      width: AppSpacing.minTapTarget,
      height: AppSpacing.minTapTarget,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(AppSpacing.minTapTarget),
          side: BorderSide(color: colors.border),
        ),
        child: Tooltip(
          message: tooltip,
          child: Icon(
            icon,
            size: 22,
            color: onPressed == null ? colors.border : colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _NoEditionChosen extends StatelessWidget {
  const _NoEditionChosen();

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (BuildContext context) => EmptyStateView(
        icon: Icons.menu_book_outlined,
        title: 'No edition chosen yet',
        message: 'Choose a translation to begin reading.',
        action: FilledButton(
          onPressed: () => context.go(Routes.library),
          child: const Text('Open the library'),
        ),
      ),
    );
  }
}

class _TodayError extends ConsumerWidget {
  const _TodayError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void retry() => ref.read(todayControllerProvider.notifier).refresh();

    if (error is DatasetUnavailableException) {
      return ErrorStateView(
        title: 'This edition has no text yet',
        message: 'The Qur’an text for this edition has not been added to the '
            'app. Nothing is missing from your reading progress — choose '
            'another edition, or import this one.',
        detail: 'See DATA_SOURCES.md for how to import a verified edition.',
        onRetry: retry,
      );
    }

    if (error is CatalogUnavailableException) {
      return ErrorStateView(
        title: 'The library could not be loaded',
        message: 'The list of editions is missing or unreadable. Reinstalling '
            'the app restores it.',
        onRetry: retry,
      );
    }

    return ErrorStateView(
      message: 'Today’s ayah could not be opened. Your reading progress is '
          'safe.',
      onRetry: retry,
    );
  }
}

/// The restrained completion state shown once a reading is finished.
class CompletionView extends StatelessWidget {
  const CompletionView({
    required this.edition,
    required this.progress,
    required this.onReadAgain,
    required this.onChooseAnother,
    this.isPlan = false,
    super.key,
  });

  final QuranEdition edition;
  final ReadingProgress progress;

  /// Whether this is the plan's reading that was finished, rather than the
  /// Daily Ayah's.
  final bool isPlan;
  final VoidCallback onReadAgain;
  final VoidCallback onChooseAnother;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Alhamdulillah',
          style: AppTypography.pageTitle.copyWith(color: colors.accent),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          edition.isFixture
              ? 'You reached the end of ${edition.titleEnglish}.'
              : isPlan
                  ? 'You finished your plan and the whole Qur’an, reading '
                      '${edition.titleEnglish}.'
                  : 'You completed the Qur’an, reading ${edition.titleEnglish}.',
          style: AppTypography.translationBody
              .copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${Formatting.count(progress.totalRead)} ayat read.',
          style: AppTypography.metadata.copyWith(color: colors.textSecondary),
        ),
        if (progress.startedAt != null && progress.completedAt != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${Formatting.date(progress.startedAt!)} — '
            '${Formatting.date(progress.completedAt!)}',
            style: AppTypography.reference.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        const AyahDivider(),
        const SizedBox(height: AppSpacing.xxl),
        FilledButton(
          onPressed: onChooseAnother,
          child: const Text('Choose another translation'),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton(
          onPressed: onReadAgain,
          child: const Text('Read again from the beginning'),
        ),
      ],
    );
  }
}
