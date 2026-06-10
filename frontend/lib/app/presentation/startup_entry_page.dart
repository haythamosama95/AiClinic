import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Legacy pre-auth landing screen with quick access to the theme demo.
///
/// Retained for reference and manual testing; the router redirects `/` and
/// `/foundation-demo` to [AppRoutes.login] in normal application flow.
class StartupEntryPage extends ConsumerWidget {
  const StartupEntryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final themeVariant = ref.watch(themeVariantProvider);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(SpacingTokens.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('AiClinic', style: theme.textTheme.headlineLarge, textAlign: TextAlign.center),
                const SizedBox(height: SpacingTokens.sm),
                Text(
                  'Clinic workstation foundation',
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: SpacingTokens.xxl),
                FilledButton.icon(
                  onPressed: () => context.go(AppRoutes.foundationDemo),
                  icon: const Icon(Icons.palette_outlined),
                  label: const Text('View theme showcase'),
                ),
                const SizedBox(height: SpacingTokens.md),
                OutlinedButton(onPressed: () => context.go(AppRoutes.login), child: const Text('Sign in')),
                const SizedBox(height: SpacingTokens.xl),
                Text('Theme variant', style: theme.textTheme.titleMedium),
                const SizedBox(height: SpacingTokens.md),
                AppSelectTileGroup<AppThemeVariant>(
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
                const SizedBox(height: SpacingTokens.lg),
                Text('Appearance', style: theme.textTheme.titleMedium),
                const SizedBox(height: SpacingTokens.md),
                AppSelectTileGroup<ThemeMode>(
                  mode: AppSelectGroupMode.radio,
                  options: [
                    for (final mode in ThemeMode.values) AppSelectOption(value: mode, label: themeModeLabel(mode)),
                  ],
                  values: {themeMode},
                  onChanged: (values) {
                    if (values.isNotEmpty) setAppThemeMode(ref, values.first);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
