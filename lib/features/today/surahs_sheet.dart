import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/edition_providers.dart';
import '../../app/providers.dart';
import '../../core/utils/formatting.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/surah.dart';
import '../../domain/repositories/quran_repository.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import 'today_controller.dart';

/// The surah index: 114 rows, each jumping to the first ayah of that surah.
///
/// Deliberately behind an icon rather than on the reading screen: the app is
/// built around reading one ayah at a time in order, and a table of contents on
/// the page would invite skimming. It is here for the reader who wants it.
abstract final class SurahsSheet {
  /// Opens the surah index for [editionId].
  static Future<void> open(BuildContext context, String editionId) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      builder: (BuildContext context) => _SurahsList(editionId: editionId),
    );
  }
}

class _SurahsList extends ConsumerWidget {
  const _SurahsList({required this.editionId});

  final String editionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppColors colors = context.colors;
    final List<Surah> surahs =
        ref.watch(surahsProvider(editionId)).value ?? const <Surah>[];
    final int? currentSurah =
        ref.watch(todayControllerProvider).value?.ayah?.surahNumber;

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
                AppSpacing.md,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  'Surahs',
                  style: AppTypography.sectionTitle
                      .copyWith(color: colors.textPrimary),
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                itemCount: surahs.length,
                separatorBuilder: (BuildContext context, int index) => Divider(
                  height: 1,
                  color: colors.border,
                  indent: AppSpacing.gutter,
                  endIndent: AppSpacing.gutter,
                ),
                itemBuilder: (BuildContext context, int index) {
                  final Surah surah = surahs[index];
                  return _SurahRow(
                    surah: surah,
                    isCurrent: surah.number == currentSurah,
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

class _SurahRow extends ConsumerStatefulWidget {
  const _SurahRow({required this.surah, required this.isCurrent});

  final Surah surah;
  final bool isCurrent;

  @override
  ConsumerState<_SurahRow> createState() => _SurahRowState();
}

class _SurahRowState extends ConsumerState<_SurahRow> {
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final Surah surah = widget.surah;
    final Color titleColour =
        widget.isCurrent ? colors.accent : colors.textPrimary;

    final List<String> details = <String>[
      if (surah.revelationPlace != RevelationPlace.unknown)
        surah.revelationPlace.label,
      if (surah.ayahCount > 0) '${Formatting.count(surah.ayahCount)} ayat',
    ];

    return Semantics(
      button: true,
      selected: widget.isCurrent,
      child: InkWell(
        onTap: _opening ? null : _open,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gutter,
            vertical: AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 34,
                child: Text(
                  '${surah.number}',
                  style: AppTypography.metadata.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      surah.displayName.isEmpty
                          ? 'Surah ${surah.number}'
                          : surah.displayName,
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
                  ],
                ),
              ),
              if (surah.nameArabic.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsetsDirectional.only(start: AppSpacing.sm),
                  child: Text(
                    surah.nameArabic,
                    textDirection: TextDirection.rtl,
                    locale: const Locale('ar'),
                    style: AppTypography.arabicTitle.copyWith(
                      color: colors.textSecondary,
                    ),
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

  /// Moves the reader to the first ayah of the surah.
  ///
  /// Browsing, not reading: nothing between here and there is marked, exactly
  /// as with the Previous and Next controls.
  Future<void> _open() async {
    setState(() => _opening = true);
    final NavigatorState navigator = Navigator.of(context);
    final QuranRepository repository = ref.read(quranRepositoryProvider);

    final int? ordinal = await repository.firstOrdinalOfSurah(
      widget.surah.editionId,
      widget.surah.number,
    );
    // A surah with no ayat stored against it stays put rather than sending the
    // reader somewhere arbitrary.
    if (ordinal == null) {
      if (mounted) setState(() => _opening = false);
      return;
    }

    await ref.read(todayControllerProvider.notifier).goTo(ordinal);
    navigator.pop();
  }
}
