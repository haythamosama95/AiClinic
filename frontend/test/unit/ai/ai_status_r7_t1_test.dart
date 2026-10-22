import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/ai_shell_status_provider.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/features/ai/availability/ai_status_snapshot.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

// R7-T1 coverage: the shell status gate and the host apply plan (pure helpers), plus the
// app-shell notifier's identity reset and transient-failure retention. Widget-level host
// behaviour is covered in the widget tests, not here.

const _identityA = AiStatusIdentity(userId: 'staff-a', organizationId: 'org-1', role: 'doctor');
const _identityB = AiStatusIdentity(userId: 'staff-b', organizationId: 'org-1', role: 'administrator');

AiAvailability _ready({List<AiStatusNotice> notices = const [], String? reason}) {
  return AiAvailability(
    enrolled: true,
    platformBaseUrl: 'https://ai.example.test',
    notices: notices,
    reason: reason,
  );
}

AiAvailability _unavailable() => const AiAvailability(enrolled: false, reason: 'coverage_lapsed');

/// Returns queued availability values in order; an Object entry is thrown instead.
class _ScriptedReader implements AiAvailabilityReader {
  _ScriptedReader(this._responses);

  final List<Object> _responses;
  int calls = 0;

  @override
  Future<AiAvailability> read() async {
    final index = calls < _responses.length ? calls : _responses.length - 1;
    calls++;
    final next = _responses[index];
    if (next is AiAvailability) {
      return next;
    }
    throw next;
  }
}

void main() {
  test('R7-T1 plan: notices-only apply keeps the context key and does not recompose', () {
    final current = AiStatusSnapshot(identity: _identityA, availability: _ready());
    final key = aiStatusContextKey(current);

    final boundaryNotice = AiStatusSnapshot(
      identity: _identityA,
      availability: _ready(
        notices: const [
          AiStatusNotice(code: 'allowance_low', audience: 'staff', channel: 'banner', graceDaysLeft: 3),
        ],
      ),
    );

    // Same readiness/context key: the resolver is kept and only notices change.
    expect(aiStatusContextKey(boundaryNotice), key);
    expect(
      planAiStatusApply(currentContextKey: key, denialRetained: false, status: boundaryNotice),
      AiStatusApplyPlan.noticesOnly,
    );
  });

  test('R7-T1 plan: denial is retained while reported, lapse and recovery recompose', () {
    final readyKey = aiStatusContextKey(AiStatusSnapshot(availability: _ready()));

    // A refreshed status that still reports the coverage denial keeps the denial visible.
    final stillDenied = AiStatusSnapshot(identity: _identityA, availability: _ready(reason: 'allowance_exhausted'));
    expect(
      planAiStatusApply(currentContextKey: readyKey, denialRetained: true, status: stillDenied),
      AiStatusApplyPlan.retainDenial,
    );

    // A refreshed status showing lapse hides AI: the host recomposes into the hidden state.
    final lapsed = AiStatusSnapshot(identity: _identityA, availability: _unavailable());
    expect(
      planAiStatusApply(currentContextKey: readyKey, denialRetained: true, status: lapsed),
      AiStatusApplyPlan.recomposeHost,
    );

    // Paid recovery: a fresh available status without a denial reason recomposes once.
    final lapsedKey = aiStatusContextKey(lapsed);
    final recovered = AiStatusSnapshot(identity: _identityA, availability: _ready());
    expect(
      planAiStatusApply(currentContextKey: lapsedKey, denialRetained: true, status: recovered),
      AiStatusApplyPlan.recomposeHost,
    );
  });

  test('R7-T1 gate: late read is dropped after an identity switch and on sign-out', () {
    final gate = AiStatusFetchGate();

    final lateReadA = gate.begin(_identityA);
    final currentB = gate.begin(_identityB);
    expect(gate.isCurrent(_identityA, lateReadA), isFalse, reason: 'identity A read is stale after switch to B');
    expect(gate.isCurrent(_identityB, currentB), isTrue);

    // Overlapping refreshes for the same identity: only the newest generation publishes.
    final olderB = gate.begin(_identityB);
    final newestB = gate.begin(_identityB);
    expect(gate.isCurrent(_identityB, currentB), isFalse);
    expect(gate.isCurrent(_identityB, olderB), isFalse);
    expect(gate.isCurrent(_identityB, newestB), isTrue);

    // Sign-out invalidates every in-flight read.
    gate.invalidate();
    expect(gate.isCurrent(_identityB, newestB), isFalse);
    expect(gate.identity, isNull);
  });

  test('R7-T1 plan: update-required and no-status states never change a ready host', () {
    const updateRequired = AiStatusSnapshot(identity: _identityA, updateRequired: true);
    expect(aiStatusContextKey(updateRequired), 'update-required');
    expect(
      planAiStatusApply(currentContextKey: 'ready|https://ai.example.test', denialRetained: false, status: updateRequired),
      AiStatusApplyPlan.updateRequired,
    );

    // No valid status yet: the host keeps its current state instead of changing mode.
    expect(
      planAiStatusApply(currentContextKey: null, denialRetained: false, status: AiStatusSnapshot.empty),
      AiStatusApplyPlan.awaitStatus,
    );
  });

  test('R7-T1 plan: transient-failure snapshot keeps availability and does not recompose', () {
    // A transient failure keeps the latest valid availability and exposes staleness only.
    final transientFailure = AiStatusSnapshot(
      identity: _identityA,
      availability: _ready(),
      refreshFailed: true,
    );
    expect(
      planAiStatusApply(
        currentContextKey: aiStatusContextKey(transientFailure),
        denialRetained: false,
        status: transientFailure,
      ),
      AiStatusApplyPlan.noticesOnly,
    );
  });

  group('R7-T1 AiShellStatusNotifier', () {
    ProviderContainer containerWith(_ScriptedReader reader) {
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => TestAuthSessionNotifier()),
          aiShellStatusReaderProvider.overrideWithValue(reader),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('identity switch while still ready resets and refreshes for the new identity', () async {
      final reader = _ScriptedReader([_ready(), _ready(reason: 'allowance_low')]);
      final container = containerWith(reader);
      final session = container.read(authSessionProvider.notifier) as TestAuthSessionNotifier;
      session.setAuthenticated();
      container.read(aiShellStatusNotifierProvider);
      await container.read(aiShellStatusRefreshProvider)();

      final first = aiStatusIdentityFor(container.read(authSessionProvider));
      expect(container.read(aiShellStatusNotifierProvider).identity, first);

      session.setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(role: StaffRole.doctor),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final second = aiStatusIdentityFor(container.read(authSessionProvider));
      expect(second, isNot(first));
      expect(reader.calls, 2, reason: 'identity change while ready triggers one refresh');
      expect(container.read(aiShellStatusNotifierProvider).identity, second);
    });

    test('sign-out clears status without a refresh', () async {
      final reader = _ScriptedReader([_ready()]);
      final container = containerWith(reader);
      final session = container.read(authSessionProvider.notifier) as TestAuthSessionNotifier;
      session.setAuthenticated();
      container.read(aiShellStatusNotifierProvider);
      await container.read(aiShellStatusRefreshProvider)();
      expect(container.read(aiShellStatusNotifierProvider).availability, isNotNull);

      session.setUnauthenticated();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(aiShellStatusNotifierProvider).identity, isNull);
      expect(container.read(aiShellStatusNotifierProvider).availability, isNull);
      expect(reader.calls, 1);
    });

    test('transient failure keeps the last valid availability and marks it stale', () async {
      final reader = _ScriptedReader([_ready(), StateError('network down')]);
      final container = containerWith(reader);
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setAuthenticated();
      container.read(aiShellStatusNotifierProvider);
      final refresh = container.read(aiShellStatusRefreshProvider);
      await refresh();
      final valid = container.read(aiShellStatusNotifierProvider).availability;
      expect(valid, isNotNull);

      await refresh();
      final snapshot = container.read(aiShellStatusNotifierProvider);
      expect(snapshot.availability, same(valid));
      expect(snapshot.refreshFailed, isTrue);
      expect(snapshot.updateRequired, isFalse);
    });

    test('update-required survives a transient failure until a fresh status clears it', () async {
      final reader = _ScriptedReader([
        const ContractVersionUnsupportedException(),
        StateError('network down'),
        _ready(),
      ]);
      final container = containerWith(reader);
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setAuthenticated();
      container.read(aiShellStatusNotifierProvider);
      final refresh = container.read(aiShellStatusRefreshProvider);

      await refresh();
      expect(container.read(aiShellStatusNotifierProvider).updateRequired, isTrue);

      await refresh();
      final afterFailure = container.read(aiShellStatusNotifierProvider);
      expect(afterFailure.updateRequired, isTrue, reason: 'transient failure must not clear update-required');
      expect(afterFailure.refreshFailed, isTrue);

      await refresh();
      final recovered = container.read(aiShellStatusNotifierProvider);
      expect(recovered.updateRequired, isFalse);
      expect(recovered.availability, isNotNull);
    });
  });
}
