import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/core/ui/ui.dart';

import 'settings_cards_grid.dart';
import 'settings_navigation_card.dart';

/// General settings tab: appearance and workstation preferences.
class SettingsGeneralTabContent extends ConsumerWidget {
  const SettingsGeneralTabContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final colors = context.colors;
    final typography = context.typography;

    return AppScrollArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s6),
        child: SettingsCardsGrid(
          children: [
            AppCard(
              title: 'Appearance',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppFormField(
                    label: 'Color mode',
                    hint: 'Switch between light and dark appearance.',
                    child: AppSegmentedControl<ThemeMode>(
                      options: [
                        for (final mode in ThemeMode.values)
                          AppSegmentedOption(value: mode, label: themeModeLabel(mode)),
                      ],
                      value: themeMode,
                      onChanged: (mode) => setAppThemeMode(ref, mode),
                      semanticLabel: 'Color mode',
                    ),
                  ),
                ],
              ),
            ),
            SettingsNavigationCard(
              title: 'Idle sign-out',
              description:
                  'Configure how long this workstation waits before signing out when the app is idle.',
              icon: LucideIcons.timer,
              onTap: () => context.nav.goSettingsIdleTimeout(),
            ),
            AppCard(
              title: 'Workstation preferences',
              child: Text(
                'Theme and idle timeout apply to this device only.',
                style: typography.bodySm.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
