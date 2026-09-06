import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/edition_providers.dart';
import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../core/utils/formatting.dart';
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/entities/user_preferences.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/notice_banner.dart';
import '../../shared/widgets/progress_bar.dart';
import '../../shared/widgets/state_views.dart';
import '../today/today_controller.dart';

/// One edition in full: description, size, attribution and progress, with a
/// single clear call to action.
class EditionDetailsScreen extends ConsumerWidget {
  const EditionDetailsScreen({required this.editionId, super.key});

  final String editionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<QuranEdition?> edition =
        ref.watch(editionProvider(editionId));

    return AppPage(
      title: edition.value?.titleEnglish ?? 'Edition',
      showBackButton: true,
      child: edition.when(
        loading: () => const LoadingView(),
        error: (Object error, StackTrace stack) => ErrorStateView(
          message: 'This edition could not be loaded.',
          onRetry: () => ref.invalidate(editionsProvider),
        ),
        data: (QuranEdition? value) {
          if (value == null) {
            return const ErrorStateView(
              title: 'Edition not found',
              message: 'This edition is no longer in the library.',
            );
          }
          return _Details(edition: value);
        },
      ),
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details({required this.edition});

  final QuranEdition edition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = context.colors;
    final AsyncValue<ReadingProgress> progress =
        ref.watch(editionProgressProvider(edition.id));
    final String? currentId = ref.watch(
      userPreferencesProvider
          .select((UserPreferences prefs) => prefs.currentEditionId),
    );
    final bool isCurrent = currentId == edition.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (edition.titleArabic.isNotEmpty)
          Directionality(
            textDirection: TextDirection.rtl,
            child: Text(
              edition.titleArabic,
              locale: const Locale('ar'),
              style: AppTypography.arabicTitle.copyWith(
                fontSize: 22,
                color: colors.textPrimary,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _subtitle(edition),
          style: AppTypography.metadata.copyWith(color: colors.textSecondary),
        ),
        if (edition.isFixture) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          const NoticeBanner(
            tone: NoticeTone.warning,
            title: 'Development data',
            message: 'The text in this edition is placeholder content for '
                'building and testing. It is not the Qur’an.',
          ),
        ] else if (!edition.isReadable) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          const NoticeBanner(
            title: 'Dataset not installed',
            message: 'The app knows about this edition but has no text for it '
                'yet. See DATA_SOURCES.md for how to import one.',
          ),
        ],
        if (edition.description.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          Text(
            edition.description,
            style: AppTypography.body.copyWith(
              color: colors.textPrimary,
              height: 1.7,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        progress.when(
          loading: () => const SizedBox.shrink(),
          error: (Object error, StackTrace stack) => const SizedBox.shrink(),
          data: (ReadingProgress value) {
            if (!value.hasStarted && value.totalRead == 0) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: ReadingProgressBar(
                read: value.totalRead,
                total: value.totalAyah,
                showPercentage: true,
              ),
            );
          },
        ),
        if (edition.isReadable)
          FilledButton(
            onPressed: () => _startReading(context, ref),
            child: Text(_ctaLabel(progress.value, isCurrent)),
          ),
        if (!edition.isFixture && !isCurrent) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Switching translation keeps your place: reading progress and '
            'saved ayat are stored against the ayah, not the translator.',
            style: AppTypography.reference.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        _SourceAttribution(edition: edition),
      ],
    );
  }

  static String _subtitle(QuranEdition edition) {
    final List<String> parts = <String>[
      if (edition.translator.isNotEmpty) edition.translator,
      edition.languageName,
      '${Formatting.count(edition.totalAyah)} ayat',
    ];
    return parts.join(' · ');
  }

  static String _ctaLabel(ReadingProgress? progress, bool isCurrent) {
    final bool started = (progress?.totalRead ?? 0) > 0;
    if (started) return isCurrent ? 'Continue reading' : 'Read in this edition';
    return 'Start reading';
  }

  /// Makes this the current edition and opens Today on it.
  Future<void> _startReading(BuildContext context, WidgetRef ref) async {
    await ref
        .read(userPreferencesProvider.notifier)
        .setCurrentEdition(edition.id);
    // Reminders carry the edition to deep-link into, so they are re-armed.
    await ref.read(notificationPreferencesProvider.notifier).applyToScheduler();
    await ref.read(todayControllerProvider.notifier).refresh();
    if (context.mounted) context.go(Routes.today);
  }
}

/// Where this edition's text came from. Always reachable, never hidden.
class _SourceAttribution extends StatelessWidget {
  const _SourceAttribution({required this.edition});

  final QuranEdition edition;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final ContentSource source = edition.source;
    final TextStyle style =
        AppTypography.reference.copyWith(color: colors.textSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Divider(color: colors.border, height: 1),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'SOURCE',
          style: AppTypography.overline.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(source.name, style: style),
        if (source.translator != null)
          Text('Translation: ${source.translator}', style: style),
        if (source.licence != null)
          Text('Licence: ${source.licence}', style: style),
        if (source.url != null) Text(source.url!, style: style),
        if (source.retrievedAt != null)
          Text('Retrieved ${Formatting.date(source.retrievedAt!)}',
              style: style),
      ],
    );
  }
}
