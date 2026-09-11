import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ai_surface_test_harness.dart';

// Keys mirrored in usage_gauge.dart / ai_feature_host_page.dart (T016–T017).
const kAiUsageGaugeKey = Key('ai_usage_gauge');
const kAiUsageGaugeGateKey = Key('ai_usage_gauge_gate');
const kAiUsageGaugeUnreachableKey = Key('ai_usage_gauge_unreachable');

const kFixtureConsumedCredits = 42;
const kFixtureCreditBudget = 10000;

void main() {
  group('usage gauge', () {
    testWidgets('gauge_renders_consumed_versus_budget', (tester) async {
      final harness = AiSurfaceHarness(reachable: true);

      await harness.pumpHost(tester);

      expect(find.byKey(kAiUsageGaugeKey), findsOneWidget);
      expect(find.text('$kFixtureConsumedCredits'), findsOneWidget);
      expect(find.text('$kFixtureCreditBudget'), findsOneWidget);
    });

    testWidgets('gauge_non_enrolled_hides_with_no_network_probe', (tester) async {
      final harness = AiSurfaceHarness(
        availability: AiAvailability.nonEnrolled,
      );

      await harness.pumpHost(tester);

      expect(find.byKey(kAiUsageGaugeKey), findsNothing);
      expect(
        harness.networkSpy.urls.where((url) => url.contains('/v1/usage')),
        isEmpty,
      );
      expect(find.byKey(kAiUsageGaugeGateKey), findsOneWidget);
    });

    testWidgets('gauge_unreachable_is_normal_state_not_error_dialog', (tester) async {
      final harness = AiSurfaceHarness(reachable: false);

      await harness.pumpHost(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(kAiDegradedUnreachableKey), findsOneWidget);
      expect(find.byKey(kAiUsageGaugeUnreachableKey), findsOneWidget);
      expect(find.text('Clinical workflows remain available.'), findsOneWidget);
    });
  });
}
