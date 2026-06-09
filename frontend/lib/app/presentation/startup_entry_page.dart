import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Pre-auth landing screen with quick access to the theme demo.
class StartupEntryPage extends ConsumerWidget {
  const StartupEntryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);

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
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: SpacingTokens.sm,
                  runSpacing: SpacingTokens.sm,
                  children: ThemeMode.values.map((mode) {
                    return ChoiceChip(
                      label: Text(themeModeLabel(mode)),
                      selected: themeMode == mode,
                      onSelected: (_) => setAppThemeMode(ref, mode),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
