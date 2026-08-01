import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/settings/data/workstation_preferences_store.dart';
import 'package:ai_clinic/features/settings/domain/format_preferences.dart';

class FormatPreferencesState {
  const FormatPreferencesState({required this.dateFormat, required this.timeFormat});

  final AppDateFormat dateFormat;
  final AppTimeFormat timeFormat;

  FormatPreferencesState copyWith({AppDateFormat? dateFormat, AppTimeFormat? timeFormat}) {
    return FormatPreferencesState(
      dateFormat: dateFormat ?? this.dateFormat,
      timeFormat: timeFormat ?? this.timeFormat,
    );
  }
}

final formatPreferencesProvider = AsyncNotifierProvider<FormatPreferencesNotifier, FormatPreferencesState>(
  FormatPreferencesNotifier.new,
);

class FormatPreferencesNotifier extends AsyncNotifier<FormatPreferencesState> {
  @override
  Future<FormatPreferencesState> build() async {
    final store = ref.read(workstationPreferencesStoreProvider);
    final dateFormat = await store.loadDateFormat();
    final timeFormat = await store.loadTimeFormat();
    return FormatPreferencesState(dateFormat: dateFormat, timeFormat: timeFormat);
  }

  Future<void> setDateFormat(AppDateFormat value) async {
    final current = state.value;
    if (current == null || current.dateFormat == value) {
      return;
    }

    state = AsyncData(current.copyWith(dateFormat: value));
    await ref.read(workstationPreferencesStoreProvider).saveDateFormat(value);
  }

  Future<void> setTimeFormat(AppTimeFormat value) async {
    final current = state.value;
    if (current == null || current.timeFormat == value) {
      return;
    }

    state = AsyncData(current.copyWith(timeFormat: value));
    await ref.read(workstationPreferencesStoreProvider).saveTimeFormat(value);
  }
}
