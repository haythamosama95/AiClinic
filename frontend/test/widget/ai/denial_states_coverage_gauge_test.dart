import 'dart:convert';

import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ai/https_submit_port.dart';
import 'package:ai_clinic/core/ai/ports.dart';
import 'package:ai_clinic/core/ai/taxonomy.dart';
import 'package:ai_clinic/core/ai/usage_summary_client.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/ai/host/ai_feature_host_page.dart';
import 'package:ai_clinic/features/ai/presentation/pages/ai_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../unit/core/ai/fakes.dart';
import 'ai_surface_test_harness.dart';
import 'usage_gauge_test.dart';

const _staffDenialMessage = 'AI not available, contact your administrator';
const _unreachableMessage = 'AI service unreachable';
const _busyMessage = 'AI busy, try again shortly';
const _renewOrBuyLabel = 'Renew or buy';
const _contactSupportLabel = 'Contact support';
const _staffForbiddenMessage = "Not included in your clinic's AI plan";
const _testPlanDisplayName = 'Standard Plan';
const _testSubscriptionRef = 'sub-ref-test-001';
const _testRetryAfter = '2026-10-08T12:00:00Z';

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

/// Pre-stream denial fake that preserves the platform wire code.
class _WireDenialSubmitPort implements HttpsSubmitPort {
  _WireDenialSubmitPort({
    required this.wireCode,
    this.retryAfter,
  });

  final String wireCode;
  final String? retryAfter;

  @override
  Future<SseConnection> submit({
    required CapabilityInvokeInput input,
    required SubmitRequestHeaders headers,
  }) async {
    throw PlatformHttpException(
      code: classifyTaxonomyCode(wireCode),
      wireCode: wireCode,
      requestReference: 'req-$wireCode',
      traceId: 'trace-$wireCode',
      retryAfter: retryAfter,
    );
  }
}

/// Coverage-shaped client for administrator gauge and subscription_ref scenarios.
class _FakeCoverageUsageClient extends UsageSummaryClient {
  _FakeCoverageUsageClient({
    required InMemoryPlatformNetworkSpy networkSpy,
    this.subscriptionRef = _testSubscriptionRef,
    this.termUsed = kFixtureConsumedCredits,
    this.termAllowance = kFixtureCreditBudget,
  }) : super(
          httpClient: MockClient((request) async {
            networkSpy.recordPlatformCall(request.url.toString());
            if (request.url.path.endsWith('/v1/coverage')) {
              return http.Response(
                jsonEncode({
                  'subscription_ref': subscriptionRef,
                  'term': {
                    'used': termUsed,
                    'allowance': termAllowance,
                    'plan_display_name': _testPlanDisplayName,
                  },
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('not found', 404);
          }),
        );

  final String subscriptionRef;
  final int termUsed;
  final int termAllowance;
}

LiveVisitSummaryComposition _buildComposition({
  required AiSurfaceHarness harness,
  required HttpsSubmitPort submitPort,
  bool staffIsAdministrator = false,
  Future<void> Function()? onStatusRefresh,
  UsageSummaryClient? usageSummaryClient,
  int? maxTransportAttempts,
  Duration Function(int attemptAfterFailure)? transportBackoff,
}) {
  final sdk = AiClientSdk(
    mintPort: harness.mintPort,
    submitPort: submitPort,
    maxTransportAttempts: maxTransportAttempts ?? kDefaultMaxTransportAttempts,
    transportBackoff: transportBackoff,
  );

  final base = buildLiveVisitSummaryComposition(
    client: _FakeSupabaseClient(),
    visitId: testVisitId,
    availabilityReader: harness.availabilityReader,
    reachabilityPort: harness.reachabilityPort,
    mintPortOverride: harness.mintPort,
    submitPortOverride: submitPort,
    networkSpy: harness.networkSpy,
    persistenceProbe: harness.persistenceProbe,
    exportProbe: harness.exportProbe,
    contextProviderOverride: harness.contextProvider,
    manifestRefreshPortOverride: harness.manifestRefreshPort,
    staffIsAdministrator: staffIsAdministrator,
    onStatusRefresh: onStatusRefresh,
    maxTransportAttempts: maxTransportAttempts,
    transportBackoff: transportBackoff,
    autoInvoke: true,
  );

  return LiveVisitSummaryComposition(
    dependencies: AiFeatureHostDependencies(
      availabilityReader: base.dependencies.availabilityReader,
      reachabilityPort: base.dependencies.reachabilityPort,
      sdk: sdk,
      contextProvider: base.dependencies.contextProvider,
      manifestRefreshPort: base.dependencies.manifestRefreshPort,
      visitId: base.dependencies.visitId,
      requiredContextKeys: base.dependencies.requiredContextKeys,
      networkSpy: base.dependencies.networkSpy,
      persistenceProbe: base.dependencies.persistenceProbe,
      exportProbe: base.dependencies.exportProbe,
      mintPort: base.dependencies.mintPort,
      usageSummaryClient: usageSummaryClient,
      autoInvoke: true,
      staffIsAdministrator: staffIsAdministrator,
      onStatusRefresh: onStatusRefresh,
    ),
    mintPort: harness.mintPort,
    submitPort: submitPort,
  );
}

Future<void> _pumpDenialHost(
  WidgetTester tester, {
  required LiveVisitSummaryComposition composition,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: AiFeatureHostPage(
          dependencies: composition.dependencies,
          embedded: true,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('E2E-P6.2-01', () {
    testWidgets('E2E-P6.2-01 coverage_lapsed shows staff and administrator denial states', (tester) async {
      final harness = AiSurfaceHarness();
      final submitPort = _WireDenialSubmitPort(wireCode: 'coverage_lapsed');

      await _pumpDenialHost(
        tester,
        composition: _buildComposition(
          harness: harness,
          submitPort: submitPort,
          staffIsAdministrator: false,
        ),
      );

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(_staffDenialMessage), findsOneWidget);
      expect(find.text(_renewOrBuyLabel), findsNothing);

      await _pumpDenialHost(
        tester,
        composition: _buildComposition(
          harness: harness,
          submitPort: submitPort,
          staffIsAdministrator: true,
        ),
      );

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(_staffDenialMessage), findsOneWidget);
      expect(find.text(_renewOrBuyLabel), findsOneWidget);
    });
  });

  group('E2E-P6.2-02', () {
    testWidgets('E2E-P6.2-02 allowance_exhausted refreshes status and shows role-specific denial', (tester) async {
      final harness = AiSurfaceHarness();
      final submitPort = _WireDenialSubmitPort(wireCode: 'allowance_exhausted');
      var statusRefreshCount = 0;

      await _pumpDenialHost(
        tester,
        composition: _buildComposition(
          harness: harness,
          submitPort: submitPort,
          staffIsAdministrator: false,
          onStatusRefresh: () async {
            statusRefreshCount++;
          },
        ),
      );

      expect(find.text(_staffDenialMessage), findsOneWidget);
      expect(statusRefreshCount, greaterThan(0));

      await _pumpDenialHost(
        tester,
        composition: _buildComposition(
          harness: harness,
          submitPort: submitPort,
          staffIsAdministrator: true,
          onStatusRefresh: () async {
            statusRefreshCount++;
          },
        ),
      );

      expect(find.text(_renewOrBuyLabel), findsOneWidget);
    });
  });

  group('E2E-P6.2-03', () {
    testWidgets('E2E-P6.2-03 suspended shows staff denial and administrator support details', (tester) async {
      final harness = AiSurfaceHarness();
      final submitPort = _WireDenialSubmitPort(wireCode: 'suspended');
      final coverageClient = _FakeCoverageUsageClient(networkSpy: harness.networkSpy);

      await _pumpDenialHost(
        tester,
        composition: _buildComposition(
          harness: harness,
          submitPort: submitPort,
          staffIsAdministrator: false,
          usageSummaryClient: coverageClient,
        ),
      );

      expect(find.text(_staffDenialMessage), findsOneWidget);
      expect(find.text(_contactSupportLabel), findsNothing);
      expect(find.text(_testSubscriptionRef), findsNothing);

      await _pumpDenialHost(
        tester,
        composition: _buildComposition(
          harness: harness,
          submitPort: submitPort,
          staffIsAdministrator: true,
          usageSummaryClient: coverageClient,
        ),
      );

      expect(find.text(_contactSupportLabel), findsOneWidget);
      expect(find.text(_testSubscriptionRef), findsOneWidget);
    });
  });

  group('E2E-P6.2-04', () {
    testWidgets('E2E-P6.2-04 concurrency_limited and rate_limited show retry_after for both roles', (tester) async {
      for (final wireCode in ['concurrency_limited', 'rate_limited']) {
        for (final isAdministrator in [false, true]) {
          final harness = AiSurfaceHarness();
          final submitPort = _WireDenialSubmitPort(
            wireCode: wireCode,
            retryAfter: _testRetryAfter,
          );

          await _pumpDenialHost(
            tester,
            composition: _buildComposition(
              harness: harness,
              submitPort: submitPort,
              staffIsAdministrator: isAdministrator,
            ),
          );

          expect(find.byType(AlertDialog), findsNothing);
          expect(find.textContaining(_busyMessage), findsOneWidget);
          expect(find.textContaining(_testRetryAfter), findsOneWidget);
        }
      }
    });
  });

  group('E2E-P6.2-05', () {
    testWidgets('E2E-P6.2-05 coverage_unknown and transport exhaustion show unreachable inline state', (
      tester,
    ) async {
      final coverageUnknownHarness = AiSurfaceHarness();
      await _pumpDenialHost(
        tester,
        composition: _buildComposition(
          harness: coverageUnknownHarness,
          submitPort: _WireDenialSubmitPort(wireCode: 'coverage_unknown'),
          staffIsAdministrator: false,
        ),
      );

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(_unreachableMessage), findsOneWidget);

      await _pumpDenialHost(
        tester,
        composition: _buildComposition(
          harness: coverageUnknownHarness,
          submitPort: _WireDenialSubmitPort(wireCode: 'coverage_unknown'),
          staffIsAdministrator: true,
        ),
      );

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(_unreachableMessage), findsOneWidget);

      final transportHarness = AiSurfaceHarness();
      final transportSubmitPort = FakeSubmitPort(
        script: [
          SubmitTransportFailureStep(),
          SubmitTransportFailureStep(),
        ],
      );

      for (final isAdministrator in [false, true]) {
        await _pumpDenialHost(
          tester,
          composition: _buildComposition(
            harness: transportHarness,
            submitPort: transportSubmitPort,
            staffIsAdministrator: isAdministrator,
            maxTransportAttempts: 2,
            transportBackoff: (_) => Duration.zero,
          ),
        );

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text(_unreachableMessage), findsOneWidget);
      }
    });
  });

  group('E2E-P6.2-06', () {
    testWidgets('E2E-P6.2-06 administrator gauge uses coverage; staff makes no coverage or usage calls', (
      tester,
    ) async {
      final successSubmit = FakeSubmitPort(
        script: [
          SubmitOpenStreamStep(
            streamingThenCompleted(
              provisionalText: 'draft',
              terminalText: 'done',
            ),
          ),
        ],
      );

      final adminHarness = AiSurfaceHarness();

      await _pumpDenialHost(
        tester,
        composition: _buildComposition(
          harness: adminHarness,
          submitPort: successSubmit,
          staffIsAdministrator: true,
        ),
      );

      expect(find.byKey(kAiUsageGaugeKey), findsOneWidget);
      expect(find.text('$kFixtureConsumedCredits'), findsOneWidget);
      expect(find.text('$kFixtureCreditBudget'), findsOneWidget);
      expect(
        adminHarness.networkSpy.urls.where((url) => url.contains('/v1/coverage')),
        isNotEmpty,
      );
      expect(
        adminHarness.networkSpy.urls.where((url) => url.contains('/v1/usage')),
        isEmpty,
      );

      final staffHarness = AiSurfaceHarness();

      await _pumpDenialHost(
        tester,
        composition: _buildComposition(
          harness: staffHarness,
          submitPort: successSubmit,
          staffIsAdministrator: false,
        ),
      );

      expect(find.byKey(kAiUsageGaugeKey), findsNothing);
      expect(
        staffHarness.networkSpy.urls.where((url) => url.contains('/v1/coverage')),
        isEmpty,
      );
      expect(
        staffHarness.networkSpy.urls.where((url) => url.contains('/v1/usage')),
        isEmpty,
      );
    });
  });

  group('E2E-P6.2-07', () {
    testWidgets('E2E-P6.2-07 forbidden_capability shows plan name to administrator and staff denial', (
      tester,
    ) async {
      final harness = AiSurfaceHarness();
      final submitPort = _WireDenialSubmitPort(wireCode: 'forbidden_capability');
      final coverageClient = _FakeCoverageUsageClient(networkSpy: harness.networkSpy);

      await _pumpDenialHost(
        tester,
        composition: _buildComposition(
          harness: harness,
          submitPort: submitPort,
          staffIsAdministrator: false,
          usageSummaryClient: coverageClient,
        ),
      );

      expect(find.text(_staffForbiddenMessage), findsOneWidget);
      expect(find.text(_testPlanDisplayName), findsNothing);

      await _pumpDenialHost(
        tester,
        composition: _buildComposition(
          harness: harness,
          submitPort: submitPort,
          staffIsAdministrator: true,
          usageSummaryClient: coverageClient,
        ),
      );

      expect(find.text(_testPlanDisplayName), findsOneWidget);
    });
  });
}
