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
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/entities/user_preferences.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/ayah_view.dart';
import '../../shared/widgets/notice_banner.dart';
import '../../shared/widgets/progress_bar.dart';
import '../../shared/widgets/state_views.dart';
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

    return NotificationListener<ScrollNotification>(
      // An ancestor of the page's scroll view, which is the only place these
      // notifications can be caught from.
      onNotification: (ScrollNotification notification) {
        _considerAutoMark();
        // Never absorb it: the scroll view's own listeners still need it.
        return false;
      },
      child: AppPage(
        title: 'Today’s Ayah',
        actions: <Widget>[_SurahsButton(editionId: state.value?.edition?.id)],
        child: state.when(
          loading: () => const LoadingView(),
          error: (Object error, StackTrace stack) => _TodayError(error: error),
          data: (TodayState value) =>
              _TodayBody(state: value, endOfAyahKey: _endOfAyah),
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

    final TodayState? current = ref.read(todayControllerProvider).value;
    final Ayah? ayah = current?.ayah;
    if (ayah == null || current!.isRead) return;
    if (_autoMarked.contains(ayah.id)) return;
    if (_armedFor == ayah.id) return;
    if (!_hasReachedEnd()) return;

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
    ref.read(todayControllerProvider.notifier).markRead();
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

class _TodayBody extends ConsumerWidget {
  const _TodayBody({required this.state, required this.endOfAyahKey});

  final TodayState state;

  /// Attached to the end of the ayah, so the screen above can tell when the
  /// reader has scrolled all the way through it.
  final Key endOfAyahKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final QuranEdition? edition = state.edition;
    if (edition == null) return const _NoEditionChosen();

    if (state.isComplete) {
      return CompletionView(
        edition: edition,
        progress: state.progress!,
        onReadAgain: () => ref.read(todayControllerProvider.notifier).restart(),
        onChooseAnother: () => context.go(Routes.library),
      );
    }

    final Ayah? ayah = state.ayah;
    if (ayah == null) {
      return ErrorStateView(
        title: 'This ayah could not be loaded',
        message: 'The text for position ${state.ordinal} is missing from local '
            'storage. Reinstalling the edition usually fixes this.',
        onRetry: () => ref.read(todayControllerProvider.notifier).refresh(),
      );
    }

    final UserPreferences preferences = ref.watch(userPreferencesProvider);
    final SpokenUtterance? speaking = ref.watch(speechControllerProvider);
    // A device with no voice for this translation's language gets no play
    // button at all, rather than one that would silently do nothing.
    final bool canSpeak =
        ref.watch(speechAvailableProvider(edition.languageCode)).value ?? false;
    final bool isFavourite = ref.watch(isFavouriteProvider(ayah)).value ?? false;
    final ReadingProgress progress = state.progress!;

    return GestureDetector(
      // Horizontal only, so the page still scrolls vertically — the gesture
      // arena decides which axis the reader actually moved along. Opaque so a
      // swipe works anywhere on the page, including the margins; taps still
      // reach the buttons, which are hit-tested first.
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (DragEndDetails details) =>
          _onSwipe(ref, details.primaryVelocity ?? 0),
      child: Column(
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
          // A gentle cross-fade when the ayah changes, keyed so the animation
          // runs on content change rather than on every rebuild.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: AyahView(
              key: ValueKey<String>(ayah.id),
              ayah: ayah,
              languageMode: preferences.languageMode,
              textScale: preferences.textSize.scale,
              showTransliteration: preferences.showTransliteration,
              translationIsRightToLeft: edition.isRightToLeft,
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
          ),
          // Nothing to look at: the point past which the whole ayah, citation
          // included, has been on screen.
          SizedBox(key: endOfAyahKey, height: AppSpacing.xxl),
          ReadingProgressBar(
            read: progress.totalRead,
            total: progress.totalAyah,
          ),
          const SizedBox(height: AppSpacing.xl),
          _ReadingActions(state: state),
        ],
      ),
    );
  }

  /// Minimum flick speed, in logical pixels per second, that counts as a page
  /// turn. High enough that a slow drag while reading does not move the page.
  static const double _swipeVelocity = 300;

  /// Turns the page on a flick, the way a mushaf does: left carries the reader
  /// forward, right goes back.
  ///
  /// The buttons remain the primary control — this is an accelerator, and it
  /// respects exactly the same limits at either end.
  void _onSwipe(WidgetRef ref, double velocity) {
    if (velocity.abs() < _swipeVelocity) return;
    final TodayController controller =
        ref.read(todayControllerProvider.notifier);
    if (velocity < 0) {
      if (state.hasNext) controller.goToNext();
    } else {
      if (state.hasPrevious) controller.goToPrevious();
    }
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
        Text(
          edition.titleEnglish,
          style: AppTypography.metadata.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          parts.join(' · '),
          style: AppTypography.metadata.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// Previous · Mark as read · Next.
class _ReadingActions extends ConsumerWidget {
  const _ReadingActions({required this.state});

  final TodayState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TodayController controller =
        ref.read(todayControllerProvider.notifier);
    final AppColors colors = context.colors;

    return Row(
      children: <Widget>[
        _NavButton(
          icon: Icons.chevron_left,
          tooltip: 'Previous ayah',
          onPressed: state.hasPrevious ? controller.goToPrevious : null,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: state.isRead
              ? OutlinedButton.icon(
                  onPressed: controller.markUnread,
                  icon: Icon(Icons.check, size: 18, color: colors.accent),
                  label: const Text('Read'),
                )
              : FilledButton(
                  onPressed: controller.markRead,
                  child: const Text('Mark as read'),
                ),
        ),
        const SizedBox(width: AppSpacing.md),
        _NavButton(
          icon: Icons.chevron_right,
          tooltip: 'Next ayah',
          onPressed: state.hasNext ? controller.goToNext : null,
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
    super.key,
  });

  final QuranEdition edition;
  final ReadingProgress progress;
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
