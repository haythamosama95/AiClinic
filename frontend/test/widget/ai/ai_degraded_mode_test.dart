import 'package:ai_clinic/core/ai/taxonomy.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_mode.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../unit/core/ai/fakes.dart';
import 'ai_surface_test_harness.dart';

void main() {
  const enrolled = AiAvailability(
    enrolled: true,
    platformBaseUrl: testPlatformBaseUrl,
  );

  group('resolveDegradedMode taxonomy mapping', () {
    test('capabilityUnknown_maps_to_appUpdate', () {
      expect(
        resolveDegradedMode(
          availability: enrolled,
          platformReachable: true,
          terminalFailureCode: TaxonomyCode.capabilityUnknown,
        ),
        AiDegradedMode.appUpdate,
      );
    });

    test('capabilityRetired_maps_to_appUpdate', () {
      expect(
        resolveDegradedMode(
          availability: enrolled,
          platformReachable: true,
          terminalFailureCode: TaxonomyCode.capabilityRetired,
        ),
        AiDegradedMode.appUpdate,
      );
    });

    test('providerUnavailable_maps_to_providerUnavailable', () {
      expect(
        resolveDegradedMode(
          availability: enrolled,
          platformReachable: true,
          terminalFailureCode: TaxonomyCode.providerUnavailable,
        ),
        AiDegradedMode.providerUnavailable,
      );
    });

    test('capabilityDisabled_maps_to_aiUnavailable', () {
      expect(
        resolveDegradedMode(
          availability: enrolled,
          platformReachable: true,
          terminalFailureCode: TaxonomyCode.capabilityDisabled,
        ),
        AiDegradedMode.aiUnavailable,
      );
    });
  });

  group('AI degraded mode', () {
    testWidgets('degraded_non_enrolled_hides_affordances_no_network', (tester) async {
      final harness = AiSurfaceHarness(
        availability: AiAvailability.nonEnrolled,
      );

      await harness.pumpHost(tester);

      expect(find.byKey(kAiAffordanceKey), findsNothing);
      // No AI chrome for non-enrolled clinics (§4.2).
      expect(find.byKey(kAiDegradedNonEnrolledKey), findsNothing);
      expect(find.text('AI is not enabled for this clinic.'), findsNothing);
      expect(find.text('AI Feature'), findsNothing);
      expect(harness.networkSpy.platformCallCount, 0);
      expect(harness.reachabilityPort.callCount, 0);
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

    testWidgets('degraded_app_update_shows_update_message', (tester) async {
      final harness = AiSurfaceHarness();
      await harness.pumpDegraded(tester, AiDegradedMode.appUpdate);

      expect(find.byKey(kAiDegradedAppUpdateKey), findsOneWidget);
      expect(
        find.text('Please update the app to use this AI feature.'),
        findsOneWidget,
      );
      expect(find.byKey(kAiDegradedRetryKey), findsNothing);
      expect(find.byKey(kAiDegradedAiUnavailableKey), findsNothing);
    });

    testWidgets('degraded_provider_unavailable_shows_retry', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: AiDegradedView(
              mode: AiDegradedMode.providerUnavailable,
              onRetry: () => retried = true,
              child: const Text('Clinical workflows remain available.'),
            ),
          ),
        ),
      );

      expect(find.byKey(kAiDegradedProviderUnavailableKey), findsOneWidget);
      expect(find.text('AI provider is unavailable. You can retry.'), findsOneWidget);
      expect(find.byKey(kAiDegradedRetryKey), findsOneWidget);
      expect(find.byKey(kAiDegradedAiUnavailableKey), findsNothing);

      await tester.tap(find.byKey(kAiDegradedRetryKey));
      await tester.pump();
      expect(retried, isTrue);
    });

    testWidgets('bootstrap_availability_read_failure_fail_closed', (tester) async {
      final harness = AiSurfaceHarness(
        availabilityThrowOnRead: StateError('rpc unavailable'),
      );

      await harness.pumpHost(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('ai_host_loading')), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(kAiAffordanceKey), findsNothing);
      expect(find.text('AI Feature'), findsNothing);
    });

    // T18/T19 + §5.4 branches: drive FailedEvent through the SDK into the host.
    testWidgets('surface_installation_suspended_hides_ai_features', (tester) async {
      final harness = AiSurfaceHarness(
        availability: enrolled,
        submitScript: [
          SubmitOpenStreamStep(
            failedStream(code: TaxonomyCode.installationSuspended, requestReference: 'req-sus'),
          ),
        ],
      );

      await harness.pumpHost(tester);

      expect(find.byKey(kAiDegradedInstallationSuspendedKey), findsOneWidget);
      expect(find.byKey(kAiAffordanceKey), findsNothing);
      expect(find.text('Clinical workflows remain available.'), findsOneWidget);
    });

    testWidgets('surface_forbidden_capability_hides_affordance', (tester) async {
      final harness = AiSurfaceHarness(
        availability: enrolled,
        submitScript: [
          SubmitOpenStreamStep(
            failedStream(code: TaxonomyCode.forbiddenCapability, requestReference: 'req-forbid'),
          ),
        ],
      );

      await harness.pumpHost(tester);

      expect(find.byKey(kAiDegradedForbiddenCapabilityKey), findsOneWidget);
      expect(find.byKey(kAiAffordanceKey), findsNothing);
    });

    testWidgets('surface_quota_exhausted_from_terminal_failure', (tester) async {
      final harness = AiSurfaceHarness(
        availability: enrolled,
        submitScript: [
          SubmitOpenStreamStep(
            failedStream(code: TaxonomyCode.quotaExhausted, requestReference: 'req-quota'),
          ),
        ],
      );

      await harness.pumpHost(tester);

      expect(find.byKey(kAiDegradedQuotaKey), findsOneWidget);
      expect(find.byKey(kAiAffordanceKey), findsNothing);
    });

    testWidgets('surface_capability_unknown_shows_app_update', (tester) async {
      final harness = AiSurfaceHarness(
        availability: enrolled,
        submitScript: [
          SubmitOpenStreamStep(
            failedStream(code: TaxonomyCode.capabilityUnknown, requestReference: 'req-unknown'),
          ),
        ],
      );

      await harness.pumpHost(tester);

      expect(find.byKey(kAiDegradedAppUpdateKey), findsOneWidget);
      expect(find.byKey(kAiAffordanceKey), findsNothing);
      expect(find.byKey(kAiDegradedAiUnavailableKey), findsNothing);
    });

    testWidgets('surface_capability_retired_shows_app_update', (tester) async {
      final harness = AiSurfaceHarness(
        availability: enrolled,
        submitScript: [
          SubmitOpenStreamStep(
            failedStream(code: TaxonomyCode.capabilityRetired, requestReference: 'req-retired'),
          ),
        ],
      );

      await harness.pumpHost(tester);

      expect(find.byKey(kAiDegradedAppUpdateKey), findsOneWidget);
      expect(find.byKey(kAiAffordanceKey), findsNothing);
    });

    testWidgets('surface_provider_unavailable_shows_retry_notice', (tester) async {
      final harness = AiSurfaceHarness(
        availability: enrolled,
        submitScript: [
          SubmitOpenStreamStep(
            failedStream(code: TaxonomyCode.providerUnavailable, requestReference: 'req-prov'),
          ),
        ],
      );

      await harness.pumpHost(tester);

      expect(find.byKey(kAiDegradedProviderUnavailableKey), findsOneWidget);
      expect(find.byKey(kAiDegradedRetryKey), findsOneWidget);
      expect(find.byKey(kAiAffordanceKey), findsNothing);
    });

    testWidgets('surface_capability_disabled_shows_ai_unavailable', (tester) async {
      final harness = AiSurfaceHarness(
        availability: enrolled,
        submitScript: [
          SubmitOpenStreamStep(
            failedStream(code: TaxonomyCode.capabilityDisabled, requestReference: 'req-disabled'),
          ),
        ],
      );

      await harness.pumpHost(tester);

      expect(find.byKey(kAiDegradedAiUnavailableKey), findsOneWidget);
      expect(find.byKey(kAiAffordanceKey), findsNothing);
    });
  });
}
