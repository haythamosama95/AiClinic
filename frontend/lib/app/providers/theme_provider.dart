import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/startup_session_provider.dart';

/// Exposes the active theme mode from startup session state for feature screens.
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(startupSessionProvider).themeMode;
});

/// Updates theme mode through the startup session notifier.
void setAppThemeMode(WidgetRef ref, ThemeMode themeMode) {
  ref.read(startupSessionProvider.notifier).setThemeMode(themeMode);
}

/// Human-readable labels for theme mode chips and settings.
String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'System',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};
