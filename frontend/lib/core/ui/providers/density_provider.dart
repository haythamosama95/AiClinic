import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_clinic/core/logging/app_log.dart';

/// Shell density scale matching web `data-density` tokens.
enum AppDensity { compact, default_, comfortable }

const _densityStorageKey = 'aiclinic-density';

extension AppDensityX on AppDensity {
  String get label => switch (this) {
    AppDensity.compact => 'Compact',
    AppDensity.default_ => 'Default',
    AppDensity.comfortable => 'Comfortable',
  };

  String get wireValue => switch (this) {
    AppDensity.compact => 'compact',
    AppDensity.default_ => 'default',
    AppDensity.comfortable => 'comfortable',
  };

  double get shellTopbarHeight => switch (this) {
    AppDensity.compact => 48,
    AppDensity.default_ => 56,
    AppDensity.comfortable => 64,
  };

  double get shellNavItemHeight => switch (this) {
    AppDensity.compact => 32,
    AppDensity.default_ => 36,
    AppDensity.comfortable => 40,
  };
}

AppDensity _densityFromStored(String? stored) => switch (stored) {
  'compact' => AppDensity.compact,
  'default' => AppDensity.comfortable,
  'comfortable' => AppDensity.comfortable,
  _ => AppDensity.comfortable,
};

class AppDensityNotifier extends Notifier<AppDensity> {
  @override
  AppDensity build() {
    Future.microtask(_loadPersistedDensity);
    return AppDensity.comfortable;
  }

  Future<void> _loadPersistedDensity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_densityStorageKey);
      if (stored == null) return;
      state = _densityFromStored(stored);
    } on Exception catch (error) {
      AppLog.warning('density.load_failed reason=${error.runtimeType}');
    }
  }

  Future<void> setDensity(AppDensity density) async {
    state = density;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_densityStorageKey, density.wireValue);
    } on Exception catch (error) {
      AppLog.warning('density.save_failed reason=${error.runtimeType}');
    }
  }

  Future<void> cycle() async {
    final next = switch (state) {
      AppDensity.compact => AppDensity.default_,
      AppDensity.default_ => AppDensity.comfortable,
      AppDensity.comfortable => AppDensity.compact,
    };
    await setDensity(next);
  }
}

final appDensityProvider = NotifierProvider<AppDensityNotifier, AppDensity>(
  AppDensityNotifier.new,
);
