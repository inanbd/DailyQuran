import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Standard page chrome: a large left-aligned title, an optional subtitle, and
/// a body constrained to a comfortable reading width.
class AppPage extends StatelessWidget {
  const AppPage({
    required this.title,
    required this.child,
    this.heading,
    this.subtitle,
    this.actions,
    this.showBackButton = false,
    this.scrollable = true,
    this.fullBleed = false,
    this.padding,
    super.key,
  });

  final String title;

  /// Shown in the title's place when given — for a page whose top is a
  /// control rather than a name, like the choice between two readings.
  final Widget? heading;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;
  final bool showBackButton;

  /// When false the body is laid out without a scroll view — used by pages that
  /// manage their own scrolling.
  final bool scrollable;

  /// When true — and not [scrollable] — the body fills the page edge to edge,
  /// with no gutter and no cap on its width: for a body that lays out its own,
  /// like the reading screen, whose pages slide in from the very edge.
  final bool fullBleed;

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final EdgeInsetsGeometry effectivePadding = padding ?? appPageBodyPadding;

    final Widget header = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.lg,
        AppSpacing.gutter,
        AppSpacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (showBackButton)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
              child: _BackButton(colors: colors),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                heading ??
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: AppTypography.pageTitle
                            .copyWith(color: colors.textPrimary),
                      ),
                    ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle!,
                    style: AppTypography.metadata
                        .copyWith(color: colors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          ...?actions,
        ],
      ),
    );

    final Widget body = Padding(padding: effectivePadding, child: child);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ReadingColumn(child: header),
            Expanded(
              child: scrollable
                  ? SingleChildScrollView(
                      child: ReadingColumn(child: body),
                    )
                  : fullBleed
                      ? child
                      : ReadingColumn(child: body),
            ),
          ],
        ),
      ),
    );
  }
}

/// The padding [AppPage] gives its body: for a full-bleed body to give each of
/// its own pages, so they read exactly like any other.
const EdgeInsets appPageBodyPadding = EdgeInsets.fromLTRB(
  AppSpacing.gutter,
  AppSpacing.sm,
  AppSpacing.gutter,
  AppSpacing.xxxl,
);

/// Centres content and caps its width so lines never grow uncomfortably long
/// on tablets or large phones.
class ReadingColumn extends StatelessWidget {
  const ReadingColumn({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.readingMaxWidth),
        child: child,
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back),
      color: colors.textPrimary,
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: AppSpacing.minTapTarget,
        minHeight: AppSpacing.minTapTarget,
      ),
    );
  }
}
