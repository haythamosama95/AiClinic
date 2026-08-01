import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/locale_provider.dart';
import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/core/ui/components/app_segmented_control.dart';
import 'package:ai_clinic/features/settings/application/format_preferences_notifier.dart';
import 'package:ai_clinic/features/settings/domain/format_preferences.dart';
import 'package:ai_clinic/features/settings/presentation/components/settings_screen_primitives.dart';

/// Appearance preferences screen (web `AppearanceScreen`).
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final formatPrefs = ref.watch(formatPreferencesProvider);

    return SettingsScreenScaffold(
      header: const SettingsScreenHeader(
        icon: Icons.palette_outlined,
        title: 'Appearance',
        description: 'Set how the app looks and formats dates and times on this workstation.',
      ),
      panel: formatPrefs.when(
        data: (prefs) => SettingsContentPanel(
          child: SettingsDividedRows(
            children: [
                SettingsSettingRow(
                  title: 'Color theme',
                  description: 'Choose light, dark, or match your operating system.',
                  control: AppSegmentedControl<String>(
                    ariaLabel: 'Color theme',
                    size: AppSegmentedControlSize.sm,
                    value: _themeModeToValue(themeMode),
                    onChanged: (value) => setAppThemeMode(ref, _valueToThemeMode(value)),
                    options: const [
                      SegmentedOption(value: 'light', label: Text('Light')),
                      SegmentedOption(value: 'dark', label: Text('Dark')),
                      SegmentedOption(value: 'system', label: Text('System')),
                    ],
                  ),
                ),
                SettingsSettingRow(
                  title: 'Language',
                  description: 'Sets the interface language and text direction for your account.',
                  control: AppSegmentedControl<String>(
                    ariaLabel: 'Language',
                    size: AppSegmentedControlSize.sm,
                    value: locale.languageCode,
                    onChanged: (value) => ref.read(localeProvider.notifier).setLocale(Locale(value)),
                    options: const [
                      SegmentedOption(value: 'en', label: Text('English')),
                      SegmentedOption(value: 'ar', label: Text('العربية')),
                    ],
                  ),
                ),
                SettingsSettingRow(
                  title: 'Date format',
                  description: 'How dates appear in lists, forms, and reports.',
                  control: AppSegmentedControl<String>(
                    ariaLabel: 'Date format',
                    size: AppSegmentedControlSize.sm,
                    value: prefs.dateFormat.storageValue,
                    onChanged: (value) {
                      final parsed = AppDateFormat.tryParse(value);
                      if (parsed != null) {
                        ref.read(formatPreferencesProvider.notifier).setDateFormat(parsed);
                      }
                    },
                    options: [
                      for (final option in AppDateFormat.values)
                        SegmentedOption(value: option.storageValue, label: Text(option.label)),
                    ],
                  ),
                ),
                SettingsSettingRow(
                  title: 'Time format',
                  description: 'How clock times are shown across the app.',
                  control: AppSegmentedControl<String>(
                    ariaLabel: 'Time format',
                    size: AppSegmentedControlSize.sm,
                    value: prefs.timeFormat.storageValue,
                    onChanged: (value) {
                      final parsed = AppTimeFormat.tryParse(value);
                      if (parsed != null) {
                        ref.read(formatPreferencesProvider.notifier).setTimeFormat(parsed);
                      }
                    },
                    options: [
                      for (final option in AppTimeFormat.values)
                        SegmentedOption(value: option.storageValue, label: Text(option.label)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        loading: () => const SettingsContentPanel(child: Center(child: CircularProgressIndicator.adaptive())),
        error: (_, _) => const SettingsContentPanel(
          child: Text('Unable to load format preferences.'),
        ),
      ),
    );
  }
}

String _themeModeToValue(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
  ThemeMode.system => 'system',
};

ThemeMode _valueToThemeMode(String value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};
