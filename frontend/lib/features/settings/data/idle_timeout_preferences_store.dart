import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/settings/data/idle_timeout_preferences_store_io.dart'
    if (dart.library.html) 'package:ai_clinic/features/settings/data/idle_timeout_preferences_store_web.dart'
    as platform;

/// Persists clinic workstation idle-timeout preferences.
class IdleTimeoutPreferencesStore {
  const IdleTimeoutPreferencesStore();

  static const fileName = 'clinic-settings.json';

  Future<Duration> loadIdleDuration() => platform.loadIdleDuration();

  Future<void> saveIdleDuration(Duration duration) => platform.saveIdleDuration(duration);
}

final idleTimeoutPreferencesStoreProvider = Provider<IdleTimeoutPreferencesStore>(
  (ref) => const IdleTimeoutPreferencesStore(),
);
