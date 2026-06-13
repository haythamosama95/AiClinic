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
  group('IdleTimeoutSettingsNotifier', () {
    test('saveCustomMinutes rejects invalid input', () async {
      final store = _FakeIdleStore(const Duration(minutes: 42));
      final container = ProviderContainer(overrides: [idleTimeoutPreferencesStoreProvider.overrideWithValue(store)]);
      addTearDown(container.dispose);

      await container.read(idleTimeoutSettingsProvider.future);
      await container.read(idleTimeoutSettingsProvider.notifier).saveCustomMinutes('abc');

      final state = container.read(idleTimeoutSettingsProvider).value!;
      expect(state.errorMessage, contains('whole number between'));
      expect(store.duration, const Duration(minutes: 42));
    });

    test('saveCustomMinutes persists valid custom duration', () async {
      final store = _FakeIdleStore(const Duration(minutes: 42));
      final container = ProviderContainer(overrides: [idleTimeoutPreferencesStoreProvider.overrideWithValue(store)]);
      addTearDown(container.dispose);

      await container.read(idleTimeoutSettingsProvider.future);
      await container.read(idleTimeoutSettingsProvider.notifier).saveCustomMinutes('60');

      expect(store.duration, const Duration(minutes: 60));
      expect(container.read(idleTimeoutSettingsProvider).value!.duration, const Duration(minutes: 60));
      expect(container.read(idleTimeoutServiceProvider).idleDuration, const Duration(minutes: 60));
    });

    test('stupid usage: custom minutes overflow capped at max', () async {
      final store = _FakeIdleStore(const Duration(minutes: 15));
      final container = ProviderContainer(overrides: [idleTimeoutPreferencesStoreProvider.overrideWithValue(store)]);
      addTearDown(container.dispose);

      await container.read(idleTimeoutSettingsProvider.future);
      await container.read(idleTimeoutSettingsProvider.notifier).saveCustomMinutes('999999');

      final state = container.read(idleTimeoutSettingsProvider).value!;
      expect(state.errorMessage, contains('whole number between'));
      expect(store.duration, const Duration(minutes: 15));
    });
  });
}
