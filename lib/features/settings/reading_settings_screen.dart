import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/user_preferences.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/settings_group.dart';
import 'settings_labels.dart';

/// How much time the reader means to give the Qur'an each day, whether the
/// app congratulates them on it — and which language(s) an ayah is shown in,
/// with or without a transliteration alongside the Arabic.
class ReadingSettingsScreen extends ConsumerWidget {
  const ReadingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserPreferences preferences = ref.watch(userPreferencesProvider);
    final AppColors colors = context.colors;

    return AppPage(
      title: 'Reading',
      showBackButton: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SettingsGroup(
            title: 'Daily reading time',
            children: <Widget>[
              for (final int minutes in <int>[
                0,
                ...UserPreferences.readingMinuteChoices,
              ])
                ChoiceRow<int>(
                  label: SettingsLabels.readingMinutes(minutes),
                  description: minutes == 0
                      ? 'No time goal. Your streak follows your plan’s goal, '
                          'or your Daily Ayah if you have no plan.'
                      : null,
                  value: minutes,
                  groupValue: preferences.dailyReadingMinutes,
                  onChanged: (int value) => ref
                      .read(userPreferencesProvider.notifier)
                      .update(preferences.copyWith(dailyReadingMinutes: value)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Time counts while an ayah is on screen and you are reading it. '
            'Put your phone down for a couple of minutes and the clock waits '
            'for you.',
            style: AppTypography.reference.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsGroup(
            title: 'Encouragement',
            children: <Widget>[
              SettingsRow(
                label: 'Celebrate milestones',
                description: 'A word of congratulation every 3 days in a row, '
                    'every tenth of the Qur’an, and when you reach your '
                    'reading time or read longer than the day before.',
                trailing: Switch(
                  value: preferences.celebrations,
                  onChanged: (bool value) => ref
                      .read(userPreferencesProvider.notifier)
                      .update(preferences.copyWith(celebrations: value)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsGroup(
            title: 'Moving between ayat',
            children: <Widget>[
              for (final ReadingLayout layout in ReadingLayout.values)
                ChoiceRow<ReadingLayout>(
                  label: _layoutLabel(layout),
                  description: _layoutDescription(layout),
                  value: layout,
                  groupValue: preferences.readingLayout,
                  onChanged: (ReadingLayout value) => ref
                      .read(userPreferencesProvider.notifier)
                      .update(preferences.copyWith(readingLayout: value)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsGroup(
            title: 'Ayah text',
            children: <Widget>[
              for (final LanguageMode mode in LanguageMode.values)
                ChoiceRow<LanguageMode>(
                  label: SettingsLabels.language(mode),
                  description: _description(mode),
                  value: mode,
                  groupValue: preferences.languageMode,
                  onChanged: (LanguageMode value) => ref
                      .read(userPreferencesProvider.notifier)
                      .update(preferences.copyWith(languageMode: value)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsGroup(
            title: 'Transliteration',
            children: <Widget>[
              SettingsRow(
                label: 'Show transliteration',
                description: 'A Latin-script rendering of the Arabic, shown '
                    'only where the edition you are reading carries one.',
                trailing: Switch(
                  value: preferences.showTransliteration,
                  onChanged: (bool value) => ref
                      .read(userPreferencesProvider.notifier)
                      .update(
                        preferences.copyWith(showTransliteration: value),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsGroup(
            title: 'Word by word',
            children: <Widget>[
              SettingsRow(
                label: 'Show word by word',
                description: 'Each Arabic word with what it means on its own, '
                    'in place of the running Arabic. A reading aid, not a '
                    'second translation of the ayah.',
                trailing: Switch(
                  value: preferences.showWordByWord,
                  onChanged: (bool value) => ref
                      .read(userPreferencesProvider.notifier)
                      .update(preferences.copyWith(showWordByWord: value)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'When both are shown, the Arabic is displayed first, followed by '
            'the translation. Nothing here is generated by the app: an ayah '
            'shows only what the edition you installed actually contains.',
            style: AppTypography.reference.copyWith(
              color: colors.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  static String _layoutLabel(ReadingLayout layout) {
    switch (layout) {
      case ReadingLayout.swipe:
        return 'Swipe, one ayah at a time';
      case ReadingLayout.scroll:
        return 'Scroll, one after another';
    }
  }

  static String _layoutDescription(ReadingLayout layout) {
    switch (layout) {
      case ReadingLayout.swipe:
        return 'Each ayah on a page of its own. Swipe to turn the page, the '
            'way a gallery turns, or use the arrows.';
      case ReadingLayout.scroll:
        return 'The ayat in one column, surah after surah. An ayah counts as '
            'read once you have spent its reading time with it and scrolled '
            'on — or tap its tick.';
    }
  }

  static String? _description(LanguageMode mode) {
    switch (mode) {
      case LanguageMode.translation:
        return 'Translation only.';
      case LanguageMode.arabic:
        return 'The Arabic only.';
      case LanguageMode.both:
        return 'Arabic first, then the translation.';
    }
  }
}
