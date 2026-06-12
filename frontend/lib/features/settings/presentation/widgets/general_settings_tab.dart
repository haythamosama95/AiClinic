import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/idle_timeout_settings_card.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_cards_grid.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_section_card.dart';

/// General settings: appearance and other workstation preferences.
class GeneralSettingsTab extends ConsumerWidget {
  const GeneralSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final themeVariant = ref.watch(themeVariantProvider);

    return ListView(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      children: [
        SettingsCardsGrid(
          children: [
            SettingsSectionCard(
              title: 'Appearance',
              child: SettingsFieldsRow(
                children: [
                  SettingsField(
                    label: 'Theme',
                    description: 'Choose the color palette.',
                    child: AppSelectTileGroup<AppThemeVariant>(
                      mode: AppSelectGroupMode.radio,
                      options: [
                        for (final variant in AppThemeVariant.values)
                          AppSelectOption(value: variant, label: appThemeVariantLabel(variant)),
                      ],
                      values: {themeVariant},
                      onChanged: (values) {
                        if (values.isNotEmpty) setAppThemeVariant(ref, values.first);
                      },
                    ),
                  ),
                  SettingsField(
                    label: 'Color mode',
                    description: 'Switch between light and dark appearance.',
                    child: AppSelectTileGroup<ThemeMode>(
                      mode: AppSelectGroupMode.radio,
                      options: [
                        for (final mode in ThemeMode.values) AppSelectOption(value: mode, label: themeModeLabel(mode)),
                      ],
                      values: {themeMode},
                      onChanged: (values) {
                        if (values.isNotEmpty) setAppThemeMode(ref, values.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const IdleTimeoutSettingsCard(),
          ],
        ),
      ],
    );
  }
}
