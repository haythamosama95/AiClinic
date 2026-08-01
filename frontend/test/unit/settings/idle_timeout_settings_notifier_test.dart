import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/settings/application/idle_timeout_settings_notifier.dart';
import 'package:ai_clinic/features/settings/data/idle_timeout_preferences_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeIdleStore extends IdleTimeoutPreferencesStore {
  _FakeIdleStore(this.duration);

  Duration duration;
  int saveIdleDurationCalls = 0;

  @override
  Future<Duration> loadIdleDuration() async => duration;

  @override
  Future<void> saveIdleDuration(Duration duration) async {
    saveIdleDurationCalls++;
    this.duration = duration;
  }
}

void main() {
  group('IdleTimeoutSettingsNotifier', () {
    test('build loads duration from store and applies to idleTimeoutServiceProvider', () async {
      final store = _FakeIdleStore(const Duration(minutes: 30));
      final container = ProviderContainer(overrides: [idleTimeoutPreferencesStoreProvider.overrideWithValue(store)]);
      addTearDown(container.dispose);

      final state = await container.read(idleTimeoutSettingsProvider.future);

      expect(state.duration, const Duration(minutes: 30));
      expect(container.read(idleTimeoutServiceProvider).idleDuration, const Duration(minutes: 30));
    });

    test('selectPresetMinutes saves and updates state', () async {
      final store = _FakeIdleStore(const Duration(minutes: 15));
      final container = ProviderContainer(overrides: [idleTimeoutPreferencesStoreProvider.overrideWithValue(store)]);
      addTearDown(container.dispose);

      await container.read(idleTimeoutSettingsProvider.future);
      await container.read(idleTimeoutSettingsProvider.notifier).selectPresetMinutes(45);

      expect(store.duration, const Duration(minutes: 45));
      expect(container.read(idleTimeoutSettingsProvider).value!.duration, const Duration(minutes: 45));
      expect(container.read(idleTimeoutServiceProvider).idleDuration, const Duration(minutes: 45));
      expect(container.read(idleTimeoutSettingsProvider).value!.saveMessage, contains('45 minutes'));
    });

    test('clearSaveMessage clears saveMessage', () async {
      final store = _FakeIdleStore(const Duration(minutes: 15));
      final container = ProviderContainer(overrides: [idleTimeoutPreferencesStoreProvider.overrideWithValue(store)]);
      addTearDown(container.dispose);

      await container.read(idleTimeoutSettingsProvider.future);
      await container.read(idleTimeoutSettingsProvider.notifier).selectPresetMinutes(30);

      expect(container.read(idleTimeoutSettingsProvider).value!.saveMessage, isNotNull);

      container.read(idleTimeoutSettingsProvider.notifier).clearSaveMessage();

      expect(container.read(idleTimeoutSettingsProvider).value!.saveMessage, isNull);
      expect(container.read(idleTimeoutSettingsProvider).value!.duration, const Duration(minutes: 30));
    });

    test('saveCustomMinutes success shows saveMessage', () async {
      final store = _FakeIdleStore(const Duration(minutes: 42));
      final container = ProviderContainer(overrides: [idleTimeoutPreferencesStoreProvider.overrideWithValue(store)]);
      addTearDown(container.dispose);

      await container.read(idleTimeoutSettingsProvider.future);
      await container.read(idleTimeoutSettingsProvider.notifier).saveCustomMinutes('60');

      final state = container.read(idleTimeoutSettingsProvider).value!;
      expect(state.saveMessage, contains('60 minutes'));
      expect(state.errorMessage, isNull);
    });

    test('selectPresetMinutes when already selected still persists', () async {
      final store = _FakeIdleStore(const Duration(minutes: 30));
      final container = ProviderContainer(overrides: [idleTimeoutPreferencesStoreProvider.overrideWithValue(store)]);
      addTearDown(container.dispose);

      await container.read(idleTimeoutSettingsProvider.future);
      final callsBefore = store.saveIdleDurationCalls;
      await container.read(idleTimeoutSettingsProvider.notifier).selectPresetMinutes(30);

      expect(store.saveIdleDurationCalls, callsBefore + 1);
      expect(container.read(idleTimeoutSettingsProvider).value!.saveMessage, contains('30 minutes'));
    });

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
