import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/features/ai/availability/ai_status_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

// R7-T1 pure-logic coverage: the shell status gate and the host apply plan. Widget-level
// host harness coverage is not added here; these tests pin the decisions the host applies.

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

void main() {
  test('R7-T1: open host applies a scheduled status boundary notice without restart', () {
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

  test('R7-T1: coverage denial applies refreshed status and recovery re-offers Generate without auto-invoke', () {
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
    // The host then mounts the surface with autoInvoke false (remountedByStatus), so the
    // affordance is an explicit Generate press and never a duplicate submission.
    final lapsedKey = aiStatusContextKey(lapsed);
    final recovered = AiStatusSnapshot(identity: _identityA, availability: _ready());
    expect(
      planAiStatusApply(currentContextKey: lapsedKey, denialRetained: true, status: recovered),
      AiStatusApplyPlan.recomposeHost,
    );
  });

  test('R7-T1: late read from an earlier identity cannot overwrite current status', () {
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

  test('R7-T1: unsupported version status shows update state while clinical navigation stays available', () {
    const updateRequired = AiStatusSnapshot(identity: _identityA, updateRequired: true);
    expect(aiStatusContextKey(updateRequired), 'update-required');
    expect(
      planAiStatusApply(currentContextKey: 'ready|https://ai.example.test', denialRetained: false, status: updateRequired),
      AiStatusApplyPlan.updateRequired,
    );

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

    // No valid status yet: the host keeps its current state instead of changing mode.
    expect(
      planAiStatusApply(currentContextKey: null, denialRetained: false, status: AiStatusSnapshot.empty),
      AiStatusApplyPlan.awaitStatus,
    );
  });
}
