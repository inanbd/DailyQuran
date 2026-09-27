import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/services/reading_session.dart';
import 'reading_activity.dart';

/// Counts the time the reader spends on [child] towards their reading time.
///
/// Time counts only while all of these hold:
///
///  * [active] — there is an ayah on screen to read,
///  * the app is in the foreground,
///  * [child] is on the tab being shown — go_router keeps other tabs mounted
///    but with their tickers off, which is how this tells,
///
/// and, within that, only for so long after the reader last touched or
/// scrolled the page (see [ReadingSession]). Everything measured is handed to
/// [ReadingActivity] to keep.
class ReadingTimer extends ConsumerStatefulWidget {
  const ReadingTimer({required this.child, this.active = true, super.key});

  final Widget child;
  final bool active;

  @override
  ConsumerState<ReadingTimer> createState() => _ReadingTimerState();
}

class _ReadingTimerState extends ConsumerState<ReadingTimer>
    with WidgetsBindingObserver {
  final ReadingSession _session = ReadingSession();

  /// Looked up in [initState]: the reading measured so far is saved on the
  /// way out, when the widget can no longer look anything up.
  late final ReadingActivity _activity;
  late final DateTime Function() _clock;

  bool _foreground = true;
  bool _onScreen = true;

  @override
  void initState() {
    super.initState();
    _activity = ref.read(readingActivityProvider);
    _clock = ref.read(clockProvider);
    WidgetsBinding.instance.addObserver(this);
    final AppLifecycleState? lifecycle =
        WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onScreen = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(ReadingTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _save(_session.end(_clock()));
    super.dispose();
  }

  /// Starts or stops the clock to match whether the reading can be seen.
  void _sync() {
    final bool reading = widget.active && _foreground && _onScreen;
    if (reading && !_session.isRunning) {
      _session.begin(_clock());
    } else if (!reading && _session.isRunning) {
      _save(_session.end(_clock()));
    }
  }

  /// A sign of the reader: a touch, a scroll, a turned page.
  void _signal() {
    if (!_session.isRunning) return;
    _save(_session.activity(_clock()));
  }

  void _save(ReadingStretch? stretch) {
    if (stretch == null) return;
    unawaited(_activity.recordTime(stretch));
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (PointerDownEvent event) => _signal(),
      onPointerSignal: (PointerSignalEvent event) => _signal(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          _signal();
          // Never absorbed: auto-marking listens further up.
          return false;
        },
        child: widget.child,
      ),
    );
  }
}
