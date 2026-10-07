import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability_reader.dart';

/// Injectable status reader for the app-shell scheduler (widget tests override this).
final aiShellStatusReaderProvider = Provider<AiAvailabilityReader>((ref) {
  return SupabaseAiAvailabilityReader(client: ref.watch(supabaseClientProvider));
});

/// The one status refresh function shared by the shell and live AI composition.
typedef AiShellStatusRefresh = Future<void> Function();

final aiShellStatusRefreshProvider = Provider<AiShellStatusRefresh>((ref) {
  return ref.read(aiShellStatusNotifierProvider.notifier).refresh;
});

final aiShellStatusNotifierProvider =
    NotifierProvider<AiShellStatusNotifier, AsyncValue<AiAvailability?>>(
  AiShellStatusNotifier.new,
);

/// Schedules `get_ai_status` on open, resume, `next_change_at`, and every 5 minutes.
class AiShellStatusNotifier extends Notifier<AsyncValue<AiAvailability?>> {
  static const _periodicInterval = Duration(minutes: 5);

  Timer? _nextChangeTimer;
  Timer? _periodicTimer;

  @override
  AsyncValue<AiAvailability?> build() {
    ref.onDispose(_cancelTimers);
    return const AsyncValue.data(null);
  }

  void startPeriodicRefresh() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(_periodicInterval, (_) {
      unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    final auth = ref.read(authSessionProvider);
    if (!auth.isAuthenticated || auth.context!.needsClinicSetup) {
      return;
    }

    startPeriodicRefresh();

    try {
      final availability = await ref.read(aiShellStatusReaderProvider).read();
      state = AsyncValue.data(availability);
      _scheduleNextChange(availability.nextChangeAt);
    } catch (_) {
      // Status refresh failures must not block clinical work.
    }
  }

  void _scheduleNextChange(DateTime? nextChangeAt) {
    _nextChangeTimer?.cancel();
    if (nextChangeAt == null) {
      return;
    }
    final delay = nextChangeAt.difference(DateTime.now());
    if (delay <= Duration.zero) {
      unawaited(refresh());
      return;
    }
    _nextChangeTimer = Timer(delay, () => unawaited(refresh()));
  }

  void cancelTimers() {
    _nextChangeTimer?.cancel();
    _periodicTimer?.cancel();
    _nextChangeTimer = null;
    _periodicTimer = null;
  }

  void _cancelTimers() => cancelTimers();
}
