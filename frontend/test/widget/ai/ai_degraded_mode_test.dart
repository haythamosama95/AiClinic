import 'package:ai_clinic/core/ai/taxonomy.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_mode.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../unit/core/ai/fakes.dart';
import 'ai_surface_test_harness.dart';

void main() {
  group('AI degraded mode', () {
    testWidgets('degraded_non_enrolled_hides_affordances_no_network', (tester) async {
      final harness = AiSurfaceHarness(
        availability: AiAvailability.nonEnrolled,
      );

      await harness.pumpHost(tester);

      expect(find.byKey(kAiAffordanceKey), findsNothing);
      expect(find.byKey(kAiDegradedNonEnrolledKey), findsOneWidget);
      expect(harness.networkSpy.platformCallCount, 0);
    });

    testWidgets('availability_flag_readable_without_platform_probe', (tester) async {
      final harness = AiSurfaceHarness(
        availability: AiAvailability.nonEnrolled,
        skipReachabilityProbe: true,
      );

      await harness.pumpHost(tester);

      expect(harness.availabilityReader.readCallCount, greaterThan(0));
      expect(harness.reachabilityPort.callCount, 0);
      expect(harness.networkSpy.platformCallCount, 0);
    });

    testWidgets('degraded_unreachable_is_normal_state_not_error_dialog', (tester) async {
      final harness = AiSurfaceHarness(reachable: false);

      await harness.pumpHost(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(kAiDegradedUnreachableKey), findsOneWidget);
      expect(find.text('Clinical workflows remain available.'), findsOneWidget);
    });

    testWidgets('degraded_enrolled_reachable_shows_affordances', (tester) async {
      final harness = AiSurfaceHarness(
        submitScript: [
          SubmitOpenStreamStep(
            streamingThenCompleted(
              provisionalText: 'draft',
              terminalText: 'done',
            ),
          ),
        ],
      );

      await harness.pumpHost(tester);

      expect(find.byKey(kAiAffordanceKey), findsOneWidget);
    });

    testWidgets('degraded_quota_exhausted_distinct_state', (tester) async {
      final harness = AiSurfaceHarness();
      await harness.pumpDegraded(tester, AiDegradedMode.quotaExhausted);

      expect(find.byKey(kAiDegradedQuotaKey), findsOneWidget);
      expect(find.byKey(kAiDegradedUnreachableKey), findsNothing);
      expect(find.byKey(kAiDegradedAiUnavailableKey), findsNothing);
    });

    testWidgets('degraded_ai_unavailable_distinct_from_offline_and_quota', (tester) async {
      final harness = AiSurfaceHarness();
      await harness.pumpDegraded(tester, AiDegradedMode.aiUnavailable);

      expect(find.byKey(kAiDegradedAiUnavailableKey), findsOneWidget);
      expect(find.byKey(kAiDegradedQuotaKey), findsNothing);
      expect(find.byKey(kAiDegradedUnreachableKey), findsNothing);
    });

    testWidgets('surface_installation_suspended_hides_ai_features', (tester) async {
      final harness = AiSurfaceHarness(
        availability: const AiAvailability(
          enrolled: true,
          platformBaseUrl: testPlatformBaseUrl,
        ),
        terminalFailureCode: TaxonomyCode.installationSuspended,
      );

      await harness.pumpHost(tester);

      expect(find.byKey(kAiDegradedInstallationSuspendedKey), findsOneWidget);
      expect(find.byKey(kAiAffordanceKey), findsNothing);
      expect(find.text('Clinical workflows remain available.'), findsOneWidget);
    });

    testWidgets('surface_forbidden_capability_hides_affordance', (tester) async {
      final harness = AiSurfaceHarness(
        availability: const AiAvailability(
          enrolled: true,
          platformBaseUrl: testPlatformBaseUrl,
        ),
        terminalFailureCode: TaxonomyCode.forbiddenCapability,
      );

      await harness.pumpHost(tester);

      expect(find.byKey(kAiDegradedForbiddenCapabilityKey), findsOneWidget);
      expect(find.byKey(kAiAffordanceKey), findsNothing);
    });
  });
}
