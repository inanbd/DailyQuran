import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/edition_providers.dart';
import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../domain/entities/notification_preferences.dart';
import '../../domain/entities/quran_edition.dart';
import '../../domain/entities/user_preferences.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/settings_group.dart';
import 'settings_labels.dart';

/// The settings hub. Each row either shows a value or opens a focused screen.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserPreferences preferences = ref.watch(userPreferencesProvider);
    final NotificationPreferences notifications =
        ref.watch(notificationPreferencesProvider);
    final AsyncValue<QuranEdition?> current =
        ref.watch(currentEditionProvider);
    final AsyncValue<QuranEdition?> second =
        ref.watch(secondaryEditionProvider);
    final bool use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);

    return AppPage(
      title: 'Settings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SettingsGroup(
            title: 'Reading',
            children: <Widget>[
              SettingsRow(
                label: 'Translation',
                value: current.value?.titleEnglish ?? 'Not chosen',
                onTap: () => context.go(Routes.library),
              ),
              SettingsRow(
                label: 'Second translation',
                value: second.value?.titleEnglish ?? 'None',
                onTap: () => context.go(Routes.settingsSecondTranslation),
              ),
              SettingsRow(
                label: 'Qur’an Planner',
                value: SettingsLabels.planValue(
                  preferences.plan,
                  today: ref.watch(clockProvider)(),
                ),
                onTap: () => context.go(Routes.planner),
              ),
              SettingsRow(
                label: 'Daily reading time',
                value: SettingsLabels.readingMinutes(
                  preferences.dailyReadingMinutes,
                ),
                onTap: () => context.go(Routes.settingsReading),
              ),
              SettingsRow(
                label: 'Ayah text',
                value: SettingsLabels.language(preferences.languageMode),
                onTap: () => context.go(Routes.settingsReading),
              ),
              SettingsRow(
                label: 'Transliteration',
                value: preferences.showTransliteration ? 'On' : 'Off',
                onTap: () => context.go(Routes.settingsReading),
              ),
              SettingsRow(
                label: 'Word by word',
                value: preferences.showWordByWord ? 'On' : 'Off',
                onTap: () => context.go(Routes.settingsReading),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsGroup(
            title: 'Notifications',
            children: <Widget>[
              SettingsRow(
                label: 'Reminders',
                value: notifications.enabled ? 'On' : 'Off',
                onTap: () => context.go(Routes.settingsNotifications),
              ),
              SettingsRow(
                label: 'Frequency',
                value: SettingsLabels.frequency(notifications),
                onTap: () => context.go(Routes.settingsNotifications),
              ),
              SettingsRow(
                label: 'What it says',
                value:
                    SettingsLabels.reminderContentName(notifications.content),
                onTap: () => context.go(Routes.settingsNotifications),
              ),
              SettingsRow(
                label: notifications.laterTimes.isEmpty ? 'Time' : 'Times',
                value: SettingsLabels.reminderTimes(
                  notifications.times,
                  use24Hour: use24Hour,
                ),
                onTap: () => context.go(Routes.settingsNotifications),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsGroup(
            title: 'Appearance',
            children: <Widget>[
              SettingsRow(
                label: 'Theme',
                value: SettingsLabels.theme(preferences.themeMode),
                onTap: () => context.go(Routes.settingsAppearance),
              ),
              SettingsRow(
                label: 'Text size',
                value: SettingsLabels.textSize(preferences.textSize),
                onTap: () => context.go(Routes.settingsAppearance),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SettingsGroup(
            title: 'About',
            children: <Widget>[
              SettingsRow(
                label: 'Qur’an sources',
                onTap: () => context.go(Routes.settingsAbout),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
