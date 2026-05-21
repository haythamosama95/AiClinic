import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/settings/data/idle_timeout_preferences_store.dart';
import 'package:ai_clinic/features/settings/domain/idle_timeout_config.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

class IdleTimeoutSettingsState {
  const IdleTimeoutSettingsState({required this.duration, this.isSaving = false, this.saveMessage, this.errorMessage});

  final Duration duration;
  final bool isSaving;
  final String? saveMessage;
  final String? errorMessage;

  IdleTimeoutSettingsState copyWith({
    Duration? duration,
    bool? isSaving,
    String? saveMessage,
    String? errorMessage,
    bool clearSaveMessage = false,
    bool clearError = false,
  }) {
    return IdleTimeoutSettingsState(
      duration: duration ?? this.duration,
      isSaving: isSaving ?? this.isSaving,
      saveMessage: clearSaveMessage ? null : (saveMessage ?? this.saveMessage),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final idleTimeoutSettingsProvider = AsyncNotifierProvider<IdleTimeoutSettingsNotifier, IdleTimeoutSettingsState>(
  IdleTimeoutSettingsNotifier.new,
);

class IdleTimeoutSettingsNotifier extends AsyncNotifier<IdleTimeoutSettingsState> {
  @override
  Future<IdleTimeoutSettingsState> build() async {
    final store = ref.read(idleTimeoutPreferencesStoreProvider);
    final duration = await store.loadIdleDuration();
    ref.read(idleTimeoutServiceProvider).updateIdleDuration(duration);
    return IdleTimeoutSettingsState(duration: duration);
  }

  Future<void> selectPresetMinutes(int minutes) async {
    await _persistAndApply(IdleTimeoutConfig.clampMinutes(minutes));
  }

  void clearSaveMessage() {
    final current = state.value;
    if (current == null || current.saveMessage == null) {
      return;
    }
    state = AsyncData(current.copyWith(clearSaveMessage: true));
  }

  Future<void> saveCustomMinutes(String input) async {
    final minutes = IdleTimeoutConfig.tryParseMinutes(input);
    if (minutes == null) {
      final current = state.value;
      if (current == null) {
        return;
      }
      state = AsyncData(
        current.copyWith(
          errorMessage:
              'Enter a whole number between ${IdleTimeoutConfig.minMinutes} and ${IdleTimeoutConfig.maxMinutes} minutes.',
          clearSaveMessage: true,
        ),
      );
      return;
    }

    await _persistAndApply(Duration(minutes: minutes));
  }

  Future<void> _persistAndApply(Duration duration) async {
    final current = state.value;
    if (current == null) {
      return;
    }

    state = AsyncData(current.copyWith(isSaving: true, clearError: true, clearSaveMessage: true));

    try {
      await ref.read(idleTimeoutPreferencesStoreProvider).saveIdleDuration(duration);
      ref.read(idleTimeoutServiceProvider).updateIdleDuration(duration);
      state = AsyncData(
        IdleTimeoutSettingsState(
          duration: duration,
          saveMessage: 'Idle timeout set to ${IdleTimeoutConfig.formatDuration(duration)}.',
        ),
      );
    } catch (error) {
      state = AsyncData(
        current.copyWith(
          isSaving: false,
          errorMessage: 'Could not save settings. Check disk permissions and try again.',
        ),
      );
    }
  }
}
