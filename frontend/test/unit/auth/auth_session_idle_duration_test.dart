import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/settings/application/idle_timeout_settings_notifier.dart';
import 'package:ai_clinic/features/settings/data/idle_timeout_preferences_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeIdleStore extends IdleTimeoutPreferencesStore {
  _FakeIdleStore(this.duration);

  Duration duration;

  @override
  Future<Duration> loadIdleDuration() async => duration;

  @override
  Future<void> saveIdleDuration(Duration duration) async {
    this.duration = duration;
  }
}

void main() {
  test('idle settings load applies persisted duration to idle service', () async {
    final store = _FakeIdleStore(const Duration(minutes: 90));

    final container = ProviderContainer(overrides: [idleTimeoutPreferencesStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);

    await container.read(idleTimeoutSettingsProvider.future);

    expect(container.read(idleTimeoutServiceProvider).idleDuration, const Duration(minutes: 90));
  });

  test('saving idle settings updates idle service duration', () async {
    final store = _FakeIdleStore(const Duration(minutes: 15));

    final container = ProviderContainer(overrides: [idleTimeoutPreferencesStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);

    await container.read(idleTimeoutSettingsProvider.future);
    await container.read(idleTimeoutSettingsProvider.notifier).selectPresetMinutes(60);

    expect(container.read(idleTimeoutServiceProvider).idleDuration, const Duration(minutes: 60));
    expect(store.duration, const Duration(minutes: 60));
  });

  test('app startup loads idle settings before timer starts', () async {
    final store = _FakeIdleStore(const Duration(minutes: 90));

    final container = ProviderContainer(overrides: [idleTimeoutPreferencesStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);

    final service = container.read(idleTimeoutServiceProvider);
    expect(service.idleDuration, const Duration(minutes: 15));

    await container.read(idleTimeoutSettingsProvider.future);

    expect(service.idleDuration, const Duration(minutes: 90));
  });
}
