import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/edition_providers.dart';
import '../../app/providers.dart';
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/user_preferences.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import 'today_controller.dart';

/// Changing translation without leaving the ayah you are on.
///
/// The library is where an edition is read about; this is where it is simply
/// chosen. Switching costs nothing — progress and favourites are stored against
/// the ayah rather than the translator — so it is worth being one tap from the
/// reading surface.
abstract final class EditionsSheet {
  static Future<void> open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      builder: (BuildContext context) => const _EditionsList(),
    );
  }
}

class _EditionsList extends ConsumerWidget {
  const _EditionsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = context.colors;
    final List<QuranEdition> editions =
        ref.watch(browsableEditionsProvider).value ?? const <QuranEdition>[];
    // Only what can actually be opened: an edition whose dataset has not been
    // imported would be a dead row here.
    final List<QuranEdition> readable = editions
        .where((QuranEdition edition) => edition.isReadable)
        .toList(growable: false);
    final String? currentId = ref.watch(
      userPreferencesProvider
          .select((UserPreferences prefs) => prefs.currentEditionId),
    );

    return SafeArea(
      child: ConstrainedBox(
        // Never a full-height takeover: the ayah stays visible behind it.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.lg,
                AppSpacing.gutter,
                AppSpacing.xs,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  'Translation',
                  style: AppTypography.sectionTitle
                      .copyWith(color: colors.textPrimary),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                0,
                AppSpacing.gutter,
                AppSpacing.md,
              ),
              child: Text(
                'Your place and your saved ayat come with you.',
                style: AppTypography.reference
                    .copyWith(color: colors.textSecondary),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                itemCount: readable.length,
                separatorBuilder: (BuildContext context, int index) => Divider(
                  height: 1,
                  color: colors.border,
                  indent: AppSpacing.gutter,
                  endIndent: AppSpacing.gutter,
                ),
                itemBuilder: (BuildContext context, int index) {
                  final QuranEdition edition = readable[index];
                  return _EditionRow(
                    edition: edition,
                    isCurrent: edition.id == currentId,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditionRow extends ConsumerStatefulWidget {
  const _EditionRow({required this.edition, required this.isCurrent});

  final QuranEdition edition;
  final bool isCurrent;

  @override
  ConsumerState<_EditionRow> createState() => _EditionRowState();
}

class _EditionRowState extends ConsumerState<_EditionRow> {
  bool _switching = false;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final QuranEdition edition = widget.edition;
    final Color titleColour =
        widget.isCurrent ? colors.accent : colors.textPrimary;

    final List<String> details = <String>[
      if (edition.translator.isNotEmpty) edition.translator,
      edition.languageLabel,
    ];

    return Semantics(
      button: true,
      selected: widget.isCurrent,
      child: InkWell(
        // Tapping the one already open would only close the sheet, which the
        // reader can do by dismissing it.
        onTap: widget.isCurrent || _switching ? null : _select,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gutter,
            vertical: AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      edition.titleEnglish,
                      style: AppTypography.body.copyWith(
                        color: titleColour,
                        fontWeight: widget.isCurrent
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (details.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        details.join(' · '),
                        style: AppTypography.reference.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    if (edition.isFixture) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        'Development data, not the Qur’an',
                        style: AppTypography.reference
                            .copyWith(color: colors.warm),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.isCurrent)
                Padding(
                  padding:
                      const EdgeInsetsDirectional.only(start: AppSpacing.sm),
                  child: Icon(Icons.check, size: 18, color: colors.accent),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens this edition, keeping the reader exactly where they were.
  ///
  /// Every complete edition shares a reading scope, so no progress is touched
  /// here: only which text renders it changes.
  Future<void> _select() async {
    setState(() => _switching = true);
    final NavigatorState navigator = Navigator.of(context);
    final ProviderContainer container =
        ProviderScope.containerOf(context, listen: false);

    await container
        .read(userPreferencesProvider.notifier)
        .setCurrentEdition(widget.edition.id);
    // Reminders carry the edition to deep-link into, so they are re-armed.
    await container
        .read(notificationPreferencesProvider.notifier)
        .applyToScheduler();
    await container.read(todayControllerProvider.notifier).refresh();

    navigator.pop();
  }
}

/// The line naming the translation being read, as a control for changing it.
class EditionSwitcher extends StatelessWidget {
  const EditionSwitcher({required this.edition, super.key});

  final QuranEdition edition;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return Semantics(
      button: true,
      label: 'Translation: ${edition.titleEnglish}. Change translation.',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => EditionsSheet.open(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  edition.titleEnglish,
                  style: AppTypography.metadata
                      .copyWith(color: colors.textPrimary),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.unfold_more, size: 16, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
