import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_clinic/core/logging/app_log.dart';

const _densityStorageKey = 'aiclinic-density';

/// Shell density scale for top bar and navigation item heights.
enum AppDensity {
  compact(topbarHeight: 48, navItemHeight: 32),
  standard(topbarHeight: 56, navItemHeight: 36),
  comfortable(topbarHeight: 64, navItemHeight: 40);

  const AppDensity({required this.topbarHeight, required this.navItemHeight});

  final double topbarHeight;
  final double navItemHeight;

  String get wireValue => name;

  static AppDensity fromWire(String? value) => switch (value) {
    'compact' => AppDensity.compact,
    'standard' => AppDensity.standard,
    'default' => AppDensity.standard,
    'comfortable' => AppDensity.comfortable,
    _ => AppDensity.comfortable,
  };
}

class AppDensityNotifier extends Notifier<AppDensity> {
  @override
  AppDensity build() {
    Future.microtask(_loadPersistedDensity);
    return AppDensity.comfortable;
  }

  /// Sets shell density and persists the choice.
  Future<void> setDensity(AppDensity density) async {
    if (state == density) {
      return;
    }
    state = density;
    await _persistDensity(density);
  }

  Future<void> _loadPersistedDensity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_densityStorageKey);
      if (stored == null) {
        return;
      }
      final density = AppDensity.fromWire(stored);
      if (density == state) {
        return;
      }
      state = density;
    } on Exception catch (error) {
      AppLog.warning('ui.density.load_failed reason=${error.runtimeType}');
    }
  }

  Future<void> _persistDensity(AppDensity density) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_densityStorageKey, density.wireValue);
    } on Exception catch (error) {
      AppLog.warning('ui.density.save_failed reason=${error.runtimeType}');
    }
  }
}

/// Global shell density preference. Default is [AppDensity.comfortable].
final appDensityProvider = NotifierProvider<AppDensityNotifier, AppDensity>(
  AppDensityNotifier.new,
);
