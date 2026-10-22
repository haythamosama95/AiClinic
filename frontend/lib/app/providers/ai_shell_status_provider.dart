import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability_reader.dart';
import 'package:ai_clinic/features/ai/availability/ai_status_snapshot.dart';

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
    NotifierProvider<AiShellStatusNotifier, AiStatusSnapshot>(
  AiShellStatusNotifier.new,
);

/// R7-T1: identity of the current session, or null when no clinic context is ready.
AiStatusIdentity? aiStatusIdentityFor(AuthSessionState auth) {
  final context = auth.context;
  if (!auth.isAuthenticated || context == null || context.needsClinicSetup) {
    return null;
  }
  return AiStatusIdentity(
    userId: context.staffProfile.staffMemberId,
    organizationId: context.organizationId ?? '',
    role: context.staffProfile.role.name,
  );
}

/// Schedules `get_ai_status` on open, resume, `next_change_at`, and every 5 minutes.
///
/// R7-T1: state is scoped to one identity. Identity change or sign-out clears state,
/// cancels timers and invalidates in-flight reads; each read publishes only if its
/// identity and refresh generation are still current.
class AiShellStatusNotifier extends Notifier<AiStatusSnapshot> {
  static const _periodicInterval = Duration(minutes: 5);

  Timer? _nextChangeTimer;
  Timer? _periodicTimer;
  final _gate = AiStatusFetchGate();

  @override
  AiStatusSnapshot build() {
    ref.onDispose(_cancelTimers);
    ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
      final previousIdentity = _gate.identity;
      final identity = aiStatusIdentityFor(next);
      if (identity == previousIdentity) {
        return;
      }
      _reset();
      // A switch between two ready identities (e.g. role demotion) stays ready, so the app
      // shell does not refresh it. Refresh for the new identity here. Sign-out and
      // transitions through not-ready are refreshed by the app shell on becoming ready.
      if (identity != null && previousIdentity != null) {
        unawaited(refresh());
      }
    });
    return AiStatusSnapshot.empty;
  }

  void startPeriodicRefresh() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(_periodicInterval, (_) {
      unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    final identity = aiStatusIdentityFor(ref.read(authSessionProvider));
    if (identity == null) {
      _reset();
      return;
    }
    if (identity != _gate.identity) {
      _reset();
    }
    final generation = _gate.begin(identity);

    startPeriodicRefresh();

    try {
      final availability = await ref.read(aiShellStatusReaderProvider).read();
      if (!_isCurrent(identity, generation)) {
        return;
      }
      state = AiStatusSnapshot(identity: identity, availability: availability);
      _scheduleNextChange(availability.nextChangeAt);
    } on ContractVersionUnsupportedException {
      if (!_isCurrent(identity, generation)) {
        return;
      }
      _nextChangeTimer?.cancel();
      _nextChangeTimer = null;
      state = AiStatusSnapshot(identity: identity, updateRequired: true);
    } catch (_) {
      if (!_isCurrent(identity, generation)) {
        return;
      }
      // Transient failure: keep the latest valid data but expose staleness so clinical
      // work is never blocked by status reads. An update-required outcome stays until a fresh
      // successful status clears it.
      state = AiStatusSnapshot(
        identity: identity,
        availability: state.availability,
        updateRequired: state.updateRequired,
        refreshFailed: true,
      );
    }
  }

  bool _isCurrent(AiStatusIdentity identity, int generation) {
    if (!ref.mounted) {
      return false;
    }
    return _gate.isCurrent(identity, generation) &&
        aiStatusIdentityFor(ref.read(authSessionProvider)) == identity;
  }

  void _reset() {
    _cancelTimers();
    _gate.invalidate();
    state = AiStatusSnapshot.empty;
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
