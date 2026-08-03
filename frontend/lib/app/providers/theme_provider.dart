import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/startup_session_provider.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/theme_transition_controller.dart';

/// Exposes the active theme mode from startup session state for feature screens.
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(startupSessionProvider).themeMode;
});

/// Updates theme mode through the startup session notifier.
void setAppThemeMode(WidgetRef ref, ThemeMode themeMode) {
  ref.read(startupSessionProvider.notifier).setThemeMode(themeMode);
}

/// Toggles light/dark with a circular reveal from [origin], falling back to an instant switch.
Future<void> toggleAppThemeMode(WidgetRef ref, BuildContext context, {required Offset origin}) async {
  final isLight = Theme.of(context).brightness == Brightness.light;
  final target = isLight ? ThemeMode.dark : ThemeMode.light;

  if (AppMotion.prefersReducedMotion(context)) {
    setAppThemeMode(ref, target);
    return;
  }

  final runner = ref.read(themeTransitionRegistryProvider).runner;
  if (runner != null) {
    await runner(target, origin);
    return;
  }

  setAppThemeMode(ref, target);
}

/// Human-readable labels for theme mode chips and settings.
String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'System',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};
