import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/edition_providers.dart';
import '../../app/favourites_providers.dart';
import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/speech_providers.dart';
import '../../core/utils/formatting.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/favourite_ayah.dart';
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/user_preferences.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/ayah_view.dart';
import '../../shared/widgets/state_views.dart';

/// Saved ayat, newest first, shown in whichever translation is being read.
class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<FavouriteAyah>> favourites =
        ref.watch(favouritesProvider);

    return AppPage(
      title: 'Favourites',
      child: favourites.when(
        loading: () => const LoadingView(),
        error: (Object error, StackTrace stack) => ErrorStateView(
          message: 'Your saved ayat could not be loaded.',
          onRetry: () => ref.invalidate(favouritesProvider),
        ),
        data: (List<FavouriteAyah> value) =>
            value.isEmpty ? const _NoFavourites() : _FavouritesList(items: value),
      ),
    );
  }
}

class _FavouritesList extends ConsumerWidget {
  const _FavouritesList({required this.items});

  final List<FavouriteAyah> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserPreferences preferences = ref.watch(userPreferencesProvider);
    final SpokenUtterance? speaking = ref.watch(speechControllerProvider);
    final QuranEdition? edition = ref.watch(currentEditionProvider).value;
    final String languageCode = edition?.languageCode ?? kDefaultSpeechLanguage;
    final bool canSpeak =
        ref.watch(speechAvailableProvider(languageCode)).value ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          items.length == 1 ? '1 saved ayah' : '${items.length} saved ayat',
          style: AppTypography.metadata.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final FavouriteAyah item in items) ...<Widget>[
          _FavouriteCard(
            item: item,
            languageMode: preferences.languageMode,
            textScale: preferences.textSize.scale,
            showTransliteration: preferences.showTransliteration,
            showWordByWord: preferences.showWordByWord,
            translationIsRightToLeft: edition?.isRightToLeft ?? false,
            speaking: speaking,
            canSpeak: canSpeak,
            languageCode: languageCode,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ],
    );
  }
}

/// One saved ayah, headed by its citation and when it was saved.
class _FavouriteCard extends ConsumerWidget {
  const _FavouriteCard({
    required this.item,
    required this.languageMode,
    required this.textScale,
    required this.showTransliteration,
    required this.showWordByWord,
    required this.translationIsRightToLeft,
    required this.speaking,
    required this.canSpeak,
    required this.languageCode,
  });

  final FavouriteAyah item;
  final LanguageMode languageMode;
  final double textScale;
  final bool showTransliteration;
  final bool showWordByWord;
  final bool translationIsRightToLeft;
  final SpokenUtterance? speaking;
  final bool canSpeak;
  final String languageCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = context.colors;

    final List<String> parts = <String>[
      if (item.ayah.surahNameEnglish != null) item.ayah.surahNameEnglish!,
      item.ayah.verseKey,
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            parts.join(' · '),
            style: AppTypography.metadata.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            'Saved ${Formatting.date(item.savedAt)}',
            style: AppTypography.reference.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AyahView(
            ayah: item.ayah,
            languageMode: languageMode,
            textScale: textScale,
            showTransliteration: showTransliteration,
            showWordByWord: showWordByWord,
            translationIsRightToLeft: translationIsRightToLeft,
            // The citation is already in the card heading.
            showReference: false,
            onSpeakTranslation: canSpeak
                ? () => ref.read(speechControllerProvider.notifier).toggle(
                      item.ayah.id,
                      item.ayah.translationText ?? '',
                      languageCode: languageCode,
                    )
                : null,
            isSpeakingTranslation: speaking ==
                SpokenUtterance(
                  ayahId: item.ayah.id,
                  languageCode: languageCode,
                ),
            // Always true here: every card on this screen is a favourite, so
            // the heart is the way to remove it.
            isFavourite: true,
            onToggleFavourite: () => ref
                .read(favouritesControllerProvider.notifier)
                .toggle(item.ayah),
          ),
        ],
      ),
    );
  }
}

class _NoFavourites extends StatelessWidget {
  const _NoFavourites();

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Icons.favorite_border,
      title: 'No favourites yet',
      message: 'Tap the heart beside any ayah to keep it here. Saved ayat '
          'follow you across translations.',
      action: FilledButton(
        onPressed: () => context.go(Routes.today),
        child: const Text('Back to today’s ayah'),
      ),
    );
  }
}
