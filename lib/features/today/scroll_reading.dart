import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/favourites_providers.dart';
import '../../app/providers.dart';
import '../../app/speech_providers.dart';
import '../../domain/entities/ayah.dart';
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/entities/user_preferences.dart';
import '../../domain/services/plan_scheduler.dart';
import '../../domain/services/reading_pace.dart';
import '../../domain/services/reading_session.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/ayah_view.dart';
import '../../shared/widgets/progress_bar.dart';
import '../planner/planner_widgets.dart';
import 'editions_sheet.dart';
import 'today_controller.dart';

/// The Read tab as one continuous column: every ayah in order, surah after
/// surah, opening at the reader's place and scrolling on — or back — from
/// there.
///
/// An ayah counts as read here the way it does on a page: by being read, not
/// by being passed. Each keeps the time it has been on screen while the reader
/// is with the app, and once that has reached a steady reading of it (see
/// [ReadingPace.timeFor]) and the reader scrolls on past it, it is marked.
/// Flicking through marks nothing. A tick beside each ayah marks it, or
/// unmarks it, by hand — and an ayah the reader has unmarked is never marked
/// again behind their back.
class ScrollReading extends ConsumerStatefulWidget {
  const ScrollReading({required this.state, super.key});

  final TodayState state;

  /// How often the time each ayah spends on screen is counted.
  static const Duration tick = Duration(milliseconds: 250);

  /// How far down the column the ayah being read is taken to be: the one
  /// crossing this line is the reader's place.
  static const double readingLine = 0.25;

  @override
  ConsumerState<ScrollReading> createState() => _ScrollReadingState();
}

/// An ayah that is built — on screen, or close enough to be about to be.
class _Shown {
  _Shown({
    required this.context,
    required this.ayah,
    required this.key,
    required this.readingTime,
    required this.isRead,
  });

  final BuildContext context;
  final Ayah ayah;
  final ReadingPageKey key;
  final Duration readingTime;
  final bool isRead;
}

class _ScrollReadingState extends ConsumerState<ScrollReading>
    with WidgetsBindingObserver {
  static const Key _anchorKey = ValueKey<String>('scroll-reading-anchor');

  /// Where the column opened. It grows from here in both directions, so
  /// neither loading an ayah above nor one below moves the one being read.
  late final int _anchor = widget.state.ordinal;

  final GlobalKey _viewport = GlobalKey();
  final Map<int, _Shown> _shown = <int, _Shown>{};
  final Map<int, Duration> _seen = <int, Duration>{};

  /// Ayat this view will not mark by itself: ones it already marked, and ones
  /// the reader marked or unmarked by hand, whose word is final.
  final Set<int> _settled = <int>{};

  /// The ayah at the reading line.
  late final ValueNotifier<int> _current = ValueNotifier<int>(_anchor);

  Timer? _ticker;
  Timer? _saveSoon;
  bool _foreground = true;
  bool _onScreen = true;
  Duration _sinceActivity = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final AppLifecycleState? lifecycle =
        WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _ticker = Timer.periodic(ScrollReading.tick, (_) => _measure(count: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Another tab in front: nobody is reading this one.
    _onScreen = TickerMode.valuesOf(context).enabled;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _saveSoon?.cancel();
    _current.dispose();
    super.dispose();
  }

  void _register(int ordinal, _Shown shown) => _shown[ordinal] = shown;

  void _unregister(int ordinal, BuildContext context) {
    if (identical(_shown[ordinal]?.context, context)) _shown.remove(ordinal);
  }

  /// A touch or a scroll: the reader is here.
  void _activity() => _sinceActivity = Duration.zero;

  static Rect? _rectOf(BuildContext? context) {
    final RenderObject? box = context?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Looks at every ayah built: which is at the reading line, which have been
  /// scrolled past having been read — and, on the ticker's beat when [count],
  /// adds the time to each one on screen.
  void _measure({required bool count}) {
    if (!mounted) return;
    final Rect? view = _rectOf(_viewport.currentContext);
    if (view == null) return;

    if (count) _sinceActivity += ScrollReading.tick;
    final bool reading = count &&
        _foreground &&
        _onScreen &&
        _sinceActivity < ReadingSession.defaultIdleAfter;
    final double line = view.top + view.height * ScrollReading.readingLine;

    for (final MapEntry<int, _Shown> entry in _shown.entries.toList()) {
      final Rect? box = _rectOf(entry.value.context);
      if (box == null) continue;
      final int ordinal = entry.key;

      if (reading && box.bottom > view.top && box.top < view.bottom) {
        _seen[ordinal] = (_seen[ordinal] ?? Duration.zero) + ScrollReading.tick;
      }
      if (box.top <= line && box.bottom > line) _current.value = ordinal;
      // All of it above the top of the column: the reader has read on past.
      if (box.bottom <= view.top) _considerMarking(ordinal, entry.value);
    }
  }

  void _considerMarking(int ordinal, _Shown shown) {
    if (shown.isRead || _settled.contains(ordinal)) return;
    if ((_seen[ordinal] ?? Duration.zero) < shown.readingTime) return;
    _settled.add(ordinal);
    unawaited(_setRead(shown.ayah, shown.key, read: true));
  }

  /// The tick beside an ayah: the reader's own say, which this view then
  /// leaves alone.
  void _toggle(Ayah ayah, ReadingPageKey key, {required bool read}) {
    _settled.add(ayah.ordinal);
    unawaited(_setRead(ayah, key, read: read));
  }

  Future<void> _setRead(
    Ayah ayah,
    ReadingPageKey key, {
    required bool read,
  }) async {
    final TodayController controller =
        ref.read(todayControllerProvider.notifier);
    if (read) {
      await controller.markAyahRead(ayah);
    } else {
      await controller.markAyahUnread(ayah);
    }
    if (mounted) ref.invalidate(readingPageProvider(key));
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    _activity();
    _measure(count: false);
    if (notification is ScrollEndNotification) {
      // The place is kept once the reader stops, so it is there next time.
      _saveSoon?.cancel();
      _saveSoon = Timer(const Duration(milliseconds: 600), _savePlace);
    }
    return false;
  }

  void _savePlace() {
    if (!mounted) return;
    final int place = _current.value;
    if (place == widget.state.ordinal) return;
    unawaited(ref.read(todayControllerProvider.notifier).goTo(place));
  }

  ReadingPageKey _keyFor(int ordinal) => (
        editionId: widget.state.edition!.id,
        secondaryId: widget.state.secondaryEdition?.id,
        scope: widget.state.scope!,
        ordinal: ordinal,
      );

  Widget _item(int ordinal) => _ScrollAyah(
        key: ValueKey<int>(ordinal),
        pageKey: _keyFor(ordinal),
        edition: widget.state.edition!,
        secondaryEdition: widget.state.secondaryEdition,
        onShown: _register,
        onGone: _unregister,
        onToggleRead: _toggle,
      );

  @override
  Widget build(BuildContext context) {
    final TodayState state = widget.state;
    final int total = state.total;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _activity(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ScrollHeader(state: state, current: _current, shown: _shown),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: CustomScrollView(
                key: _viewport,
                center: _anchorKey,
                // Ayat a little way off are built ahead of time, so they are
                // there, full height, before they come into view.
                scrollCacheExtent: const ScrollCacheExtent.pixels(900),
                slivers: <Widget>[
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext context, int index) =>
                          _item(_anchor - 1 - index),
                      childCount: _anchor - 1,
                    ),
                  ),
                  SliverList(
                    key: _anchorKey,
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext context, int index) =>
                          _item(_anchor + index),
                      childCount: total - _anchor + 1,
                    ),
                  ),
                  const SliverToBoxAdapter(child: _EndOfReading()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The translation, where the reader is, and how the reading is going —
/// fixed above the column as it scrolls beneath.
class _ScrollHeader extends StatelessWidget {
  const _ScrollHeader({
    required this.state,
    required this.current,
    required this.shown,
  });

  final TodayState state;
  final ValueListenable<int> current;
  final Map<int, _Shown> shown;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final ReadingProgress progress = state.progress!;
    final ReadingPortion? portion = state.isPlan ? state.portion : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: ReadingColumn(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            0,
            AppSpacing.gutter,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: EditionSwitcher(edition: state.edition!),
                    ),
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: current,
                    builder: (BuildContext context, int ordinal, _) {
                      final Ayah? ayah =
                          shown[ordinal]?.ayah ?? state.ayah;
                      if (ayah == null) return const SizedBox.shrink();
                      return Text(
                        <String>[
                          if (ayah.surahNameEnglish != null)
                            ayah.surahNameEnglish!,
                          ayah.verseKey,
                        ].join(' · '),
                        style: AppTypography.metadata
                            .copyWith(color: colors.textSecondary),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              portion != null
                  ? ReadingProgressBar(
                      read: portion.read,
                      total: portion.target,
                      label: portion.isComplete
                          ? 'Today’s goal is done'
                          : portion.progressWords,
                    )
                  : ReadingProgressBar(
                      read: progress.totalRead,
                      total: progress.totalAyah,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One ayah of the column, with its surah's heading where a surah begins.
class _ScrollAyah extends ConsumerStatefulWidget {
  const _ScrollAyah({
    required this.pageKey,
    required this.edition,
    required this.secondaryEdition,
    required this.onShown,
    required this.onGone,
    required this.onToggleRead,
    super.key,
  });

  final ReadingPageKey pageKey;
  final QuranEdition edition;
  final QuranEdition? secondaryEdition;
  final void Function(int ordinal, _Shown shown) onShown;
  final void Function(int ordinal, BuildContext context) onGone;
  final void Function(Ayah ayah, ReadingPageKey key, {required bool read})
      onToggleRead;

  @override
  ConsumerState<_ScrollAyah> createState() => _ScrollAyahState();
}

class _ScrollAyahState extends ConsumerState<_ScrollAyah> {
  @override
  void dispose() {
    widget.onGone(widget.pageKey.ordinal, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ReadingPage? page =
        ref.watch(readingPageProvider(widget.pageKey)).value;
    final Ayah? ayah = page?.ayah;
    // Keeps roughly an ayah's height while it loads, so the column does not
    // shuffle as the text arrives.
    if (page == null || ayah == null) return const SizedBox(height: 200);

    final UserPreferences preferences = ref.watch(userPreferencesProvider);
    final QuranEdition edition = widget.edition;
    final QuranEdition? second = widget.secondaryEdition;
    final bool showsSecond =
        second != null && (page.secondaryAyah?.hasTranslation ?? false);

    widget.onShown(
      widget.pageKey.ordinal,
      _Shown(
        context: context,
        ayah: ayah,
        key: widget.pageKey,
        isRead: page.isRead,
        readingTime: ReadingPace.timeFor(
          arabic: preferences.languageMode.showsArabic || !ayah.hasTranslation
              ? ayah.arabicText
              : null,
          translations: <String?>[
            if (preferences.languageMode.showsTranslation || !ayah.hasArabic)
              ayah.translationText,
            if (preferences.languageMode.showsTranslation && showsSecond)
              page.secondaryAyah!.translationText,
          ],
        ),
      ),
    );

    final SpokenUtterance? speaking = ref.watch(speechControllerProvider);
    final bool canSpeak =
        ref.watch(speechAvailableProvider(edition.languageCode)).value ?? false;
    final bool isFavourite = ref.watch(isFavouriteProvider(ayah)).value ?? false;

    return ReadingColumn(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (ayah.ayahNumber == 1)
              _SurahHeading(
                ayah: ayah,
                editionId: edition.id,
                withBasmala: !edition.isFixture &&
                    preferences.languageMode.showsArabic &&
                    ayah.surahNumber != 1 &&
                    ayah.surahNumber != 9,
              ),
            const SizedBox(height: AppSpacing.lg),
            _AyahLine(
              ayah: ayah,
              isRead: page.isRead,
              onToggle: () => widget.onToggleRead(
                ayah,
                widget.pageKey,
                read: !page.isRead,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AyahView(
              ayah: ayah,
              languageMode: preferences.languageMode,
              textScale: preferences.textSize.scale,
              showTransliteration: preferences.showTransliteration,
              showWordByWord: preferences.showWordByWord,
              translationIsRightToLeft: edition.isRightToLeft,
              showReference: false,
              secondaryTranslation: showsSecond
                  ? SecondaryTranslation(
                      text: page.secondaryAyah!.translationText!,
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
            const SizedBox(height: AppSpacing.lg),
            Divider(color: context.colors.border, height: 1),
          ],
        ),
      ),
    );
  }
}

/// "2:255", and the tick that says whether it has been read.
class _AyahLine extends StatelessWidget {
  const _AyahLine({
    required this.ayah,
    required this.isRead,
    required this.onToggle,
  });

  final Ayah ayah;
  final bool isRead;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.accentSoft,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Text(
            ayah.verseKey,
            style: AppTypography.progressMeta.copyWith(color: colors.accent),
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: onToggle,
          icon: Icon(
            isRead ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 24,
            color: isRead ? colors.accent : colors.border,
          ),
          // Says what pressing it will do, which is what a screen reader
          // announces.
          tooltip: isRead ? 'Mark ${ayah.verseKey} as unread' : 'Mark ${ayah.verseKey} as read',
          constraints: const BoxConstraints(
            minWidth: AppSpacing.minTapTarget,
            minHeight: AppSpacing.minTapTarget,
          ),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

/// The basmala as a surah's heading: Al-Fatihah's first ayah, from the edition
/// being read, word for word. The app never writes the Qur'an itself.
final basmalaProvider = FutureProvider.autoDispose.family<String?, String>(
  (Ref ref, String editionId) async => (await ref
          .watch(quranRepositoryProvider)
          .ayahByVerseKey(editionId, '1:1'))
      ?.arabicText,
);

/// Where a surah begins: its names and, where it has one, the basmala.
class _SurahHeading extends ConsumerWidget {
  const _SurahHeading({
    required this.ayah,
    required this.editionId,
    required this.withBasmala,
  });

  final Ayah ayah;
  final String editionId;
  final bool withBasmala;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = context.colors;
    final String? basmala =
        withBasmala ? ref.watch(basmalaProvider(editionId)).value : null;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: Semantics(
        header: true,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: colors.warm.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: <Widget>[
              if (ayah.surahNameArabic != null)
                Text(
                  ayah.surahNameArabic!,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  locale: const Locale('ar'),
                  style: AppTypography.arabicTitle
                      .copyWith(color: colors.accent),
                ),
              if (ayah.surahNameEnglish != null)
                Text(
                  ayah.surahNameEnglish!,
                  textAlign: TextAlign.center,
                  style: AppTypography.sectionTitle
                      .copyWith(color: colors.textPrimary),
                ),
              if (basmala != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                const AyahDivider(),
                const SizedBox(height: AppSpacing.md),
                Text(
                  basmala,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  locale: const Locale('ar'),
                  style: AppTypography.arabicBody
                      .copyWith(color: colors.textPrimary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EndOfReading extends StatelessWidget {
  const _EndOfReading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: AyahDivider(),
    );
  }
}
