import 'package:ai_clinic/features/settings/application/format_preferences_notifier.dart';
import 'package:ai_clinic/features/settings/data/workstation_preferences_store.dart';
import 'package:ai_clinic/features/settings/domain/format_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWorkstationStore extends WorkstationPreferencesStore {
  _FakeWorkstationStore({
    this.dateFormat = AppDateFormat.dmy,
    this.timeFormat = AppTimeFormat.h12,
  });

  AppDateFormat dateFormat;
  AppTimeFormat timeFormat;

  int saveDateFormatCallCount = 0;
  int saveTimeFormatCallCount = 0;

  @override
  Future<AppDateFormat> loadDateFormat() async => dateFormat;

  @override
  Future<void> saveDateFormat(AppDateFormat value) async {
    saveDateFormatCallCount++;
    dateFormat = value;
  }

  @override
  Future<AppTimeFormat> loadTimeFormat() async => timeFormat;

  @override
  Future<void> saveTimeFormat(AppTimeFormat value) async {
    saveTimeFormatCallCount++;
    timeFormat = value;
  }
}

ProviderContainer _container(_FakeWorkstationStore store) {
  return ProviderContainer(
    overrides: [
      workstationPreferencesStoreProvider.overrideWithValue(store),
    ],
  );
}

void main() {
  group('FormatPreferencesNotifier', () {
    test('build loads date and time formats from the store', () async {
      final store = _FakeWorkstationStore(
        dateFormat: AppDateFormat.mdy,
        timeFormat: AppTimeFormat.h24,
      );
      final container = _container(store);
      addTearDown(container.dispose);

      final state = await container.read(formatPreferencesProvider.future);

      expect(state.dateFormat, AppDateFormat.mdy);
      expect(state.timeFormat, AppTimeFormat.h24);
    });

    test('setDateFormat updates state and persists', () async {
      final store = _FakeWorkstationStore();
      final container = _container(store);
      addTearDown(container.dispose);

      await container.read(formatPreferencesProvider.future);
      await container.read(formatPreferencesProvider.notifier).setDateFormat(AppDateFormat.mdy);

      expect(store.dateFormat, AppDateFormat.mdy);
      expect(container.read(formatPreferencesProvider).value!.dateFormat, AppDateFormat.mdy);
      expect(store.saveDateFormatCallCount, 1);
    });

    test('setTimeFormat updates state and persists', () async {
      final store = _FakeWorkstationStore();
      final container = _container(store);
      addTearDown(container.dispose);

      await container.read(formatPreferencesProvider.future);
      await container.read(formatPreferencesProvider.notifier).setTimeFormat(AppTimeFormat.h24);

      expect(store.timeFormat, AppTimeFormat.h24);
      expect(container.read(formatPreferencesProvider).value!.timeFormat, AppTimeFormat.h24);
      expect(store.saveTimeFormatCallCount, 1);
    });

    test('setDateFormat with same value is a no-op', () async {
      final store = _FakeWorkstationStore(dateFormat: AppDateFormat.dmy);
      final container = _container(store);
      addTearDown(container.dispose);

      await container.read(formatPreferencesProvider.future);
      await container.read(formatPreferencesProvider.notifier).setDateFormat(AppDateFormat.dmy);

      expect(store.saveDateFormatCallCount, 0);
    });

    test('setTimeFormat with same value is a no-op', () async {
      final store = _FakeWorkstationStore(timeFormat: AppTimeFormat.h12);
      final container = _container(store);
      addTearDown(container.dispose);

      await container.read(formatPreferencesProvider.future);
      await container.read(formatPreferencesProvider.notifier).setTimeFormat(AppTimeFormat.h12);

      expect(store.saveTimeFormatCallCount, 0);
    });
  });
}
