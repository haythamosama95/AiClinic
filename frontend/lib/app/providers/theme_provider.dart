import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_clinic/core/logging/app_log.dart';

const _themeModeStorageKey = 'aiclinic-theme-mode';

/// Legacy web key (`light` / `dark` only) for backward-compatible reads.
const _legacyThemeStorageKey = 'aiclinic-theme';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    Future.microtask(_loadPersistedThemeMode);
    return ThemeMode.system;
  }

  /// Updates theme mode and persists the choice.
  Future<void> setThemeMode(ThemeMode themeMode) async {
    if (state == themeMode) {
      return;
    }
    state = themeMode;
    await _persistThemeMode(themeMode);
  }

  Future<void> _loadPersistedThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_themeModeStorageKey) ?? prefs.getString(_legacyThemeStorageKey);
      if (stored == null) {
        return;
      }
      final themeMode = _themeModeFromWire(stored);
      if (themeMode == null || themeMode == state) {
        return;
      }
      state = themeMode;
    } on Exception catch (error) {
      AppLog.warning('ui.theme.load_failed reason=${error.runtimeType}');
    }
  }

  Future<void> _persistThemeMode(ThemeMode themeMode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeStorageKey, _themeModeToWire(themeMode));
    } on Exception catch (error) {
      AppLog.warning('ui.theme.save_failed reason=${error.runtimeType}');
    }
  }

  String _themeModeToWire(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };

  ThemeMode? _themeModeFromWire(String value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => null,
  };
}

/// Global theme mode preference (light / dark / system), persisted locally.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// Updates theme mode through [themeModeProvider].
void setAppThemeMode(WidgetRef ref, ThemeMode themeMode) {
  unawaited(ref.read(themeModeProvider.notifier).setThemeMode(themeMode));
}

/// Human-readable labels for theme mode chips and settings.
String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'System',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};
