import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/edition_providers.dart';
import '../../app/providers.dart';
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/user_preferences.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/settings_group.dart';
import '../../shared/widgets/state_views.dart';
import '../today/today_controller.dart';

/// Choosing a second translation to read alongside the first.
///
/// Two is the whole range this screen offers, and that is the point of it: one
/// translation is the reading, a second is a comparison, and a third would turn
/// the ayah into a table. "None" is a first-class option here rather than a way
/// of undoing a mistake — most readers want one translation, and the screen
/// should not imply otherwise.
class SecondTranslationScreen extends ConsumerWidget {
  const SecondTranslationScreen({super.key});

  /// The value [ChoiceRow] uses for "no second translation". A sentinel rather
  /// than null, because a null group value would leave every row unselected.
  static const String noneValue = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserPreferences preferences = ref.watch(userPreferencesProvider);
    final AsyncValue<List<QuranEdition>> editions =
        ref.watch(browsableEditionsProvider);
    final String? currentId = preferences.currentEditionId;

    return AppPage(
      title: 'Second translation',
      subtitle: 'Read two translations of the same ayah, one under the other.',
      showBackButton: true,
      child: editions.when(
        loading: () => const LoadingView(),
        error: (Object error, StackTrace stack) => ErrorStateView(
          title: 'The translations could not be loaded',
          message: 'The list of editions is missing or unreadable. Your '
              'reading progress is safe.',
          onRetry: () => ref.invalidate(editionsProvider),
        ),
        data: (List<QuranEdition> all) {
          // Only editions that can actually be opened, and never the one
          // already on top: a translation stacked on itself is not a second
          // reading of anything.
          //
          // Editions in another progress scope are excluded too. Ordinals only
          // line up between editions counting the same ayat, so anything else
          // would put an unrelated ayah under this one.
          final QuranEdition? current = _byId(all, currentId);
          final List<QuranEdition> offered = all
              .where((QuranEdition edition) =>
                  edition.isReadable &&
                  edition.id != currentId &&
                  (current == null || edition.scope == current.scope))
              .toList(growable: false);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (current != null) ...<Widget>[
                _FirstTranslation(edition: current),
                const SizedBox(height: AppSpacing.xl),
              ],
              SettingsGroup(
                title: 'Second translation',
                children: <Widget>[
                  ChoiceRow<String>(
                    label: 'None',
                    description: 'Just the one translation.',
                    value: noneValue,
                    groupValue: preferences.secondaryEditionId ?? noneValue,
                    onChanged: (String value) => _choose(ref, null),
                  ),
                  for (final QuranEdition edition in offered)
                    ChoiceRow<String>(
                      label: edition.titleEnglish,
                      description: edition.languageLabel,
                      value: edition.id,
                      groupValue: preferences.secondaryEditionId ?? noneValue,
                      onChanged: (String value) => _choose(ref, value),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Both translations mark the same ayah read, so your place and '
                'your saved ayat are unchanged either way.',
                style: AppTypography.reference.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static QuranEdition? _byId(List<QuranEdition> editions, String? id) {
    if (id == null) return null;
    for (final QuranEdition edition in editions) {
      if (edition.id == id) return edition;
    }
    return null;
  }

  /// Sets the second translation and rebuilds the reading behind this screen,
  /// so going back shows the change rather than the state before it.
  Future<void> _choose(WidgetRef ref, String? editionId) async {
    await ref
        .read(userPreferencesProvider.notifier)
        .setSecondaryEdition(editionId);
    await ref.read(todayControllerProvider.notifier).refresh();
  }
}

/// The translation the second one will sit under, named so the pairing is
/// obvious before it is chosen rather than after.
class _FirstTranslation extends StatelessWidget {
  const _FirstTranslation({required this.edition});

  final QuranEdition edition;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'FIRST TRANSLATION',
          style: AppTypography.overline.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          edition.titleEnglish,
          style: AppTypography.body.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }
}
