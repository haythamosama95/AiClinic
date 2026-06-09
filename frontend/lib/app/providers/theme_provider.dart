import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/startup_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/variants/app_theme_variant.dart';

/// Exposes the active theme mode from startup session state for feature screens.
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(startupSessionProvider).themeMode;
});

/// Owns the active design-system variant (clinic vs parchment).
final themeVariantProvider = NotifierProvider<ThemeVariantNotifier, AppThemeVariant>(ThemeVariantNotifier.new);

class ThemeVariantNotifier extends Notifier<AppThemeVariant> {
  @override
  AppThemeVariant build() => AppThemeVariant.clinic;

  void setVariant(AppThemeVariant variant) {
    state = variant;
  }
}

/// Updates theme mode through the startup session notifier.
void setAppThemeMode(WidgetRef ref, ThemeMode themeMode) {
  ref.read(startupSessionProvider.notifier).setThemeMode(themeMode);
}

/// Updates the active design-system variant.
void setAppThemeVariant(WidgetRef ref, AppThemeVariant variant) {
  ref.read(themeVariantProvider.notifier).setVariant(variant);
}

/// Human-readable labels for theme mode chips and settings.
String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'System',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};
