import 'dart:async';
import 'dart:convert';

import 'package:ai_clinic/core/ai/usage_summary_client.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/ai/host/ai_feature_host_page.dart';
import 'package:ai_clinic/features/ai/presentation/pages/ai_page.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/auth_test_support.dart';
import 'ai_surface_test_harness.dart';

// Mirrors the coverage fixture shape used by usage_gauge_test.dart (42 of 10000 credits).
const _coverageBody = {
  'subscription_ref': 'sub-fixture-001',
  'term': {
    'used': 42,
    'allowance': 10000,
    'plan_display_name': 'Fixture Plan',
  },
};

http.Response _coverageResponse() => http.Response(
  jsonEncode(_coverageBody),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('R7-UI1 live visit and role identity guard', () {
    test('R7-UI1: changing visit does not show previous visit AI context', () {
      final administrator = sampleAuthSessionContext(role: StaffRole.administrator);

      final visitA = liveVisitHostIdentityFor(authContext: administrator, visitId: 'visit-A');
      final visitB = liveVisitHostIdentityFor(authContext: administrator, visitId: 'visit-B');

      // A -> B must produce a different composition identity so the keyed host is replaced.
      expect(visitA == visitB, isFalse);
      expect(
        visitA,
        equals(liveVisitHostIdentityFor(authContext: administrator, visitId: 'visit-A')),
      );

      // Role changes also replace the composition, so administrator dependencies are not reused.
      final staff = liveVisitHostIdentityFor(
        authContext: sampleAuthSessionContext(role: StaffRole.doctor),
        visitId: 'visit-A',
      );
      expect(staff == visitA, isFalse);

      // No authenticated context yields a distinct, non-administrator identity.
      final signedOut = liveVisitHostIdentityFor(authContext: null, visitId: 'visit-A');
      expect(signedOut == visitA, isFalse);
      expect(signedOut.staffIsAdministrator, isFalse);
    });

    testWidgets('R7-UI1: role downgrade drops an in-flight administrator coverage read', (tester) async {
      final harness = AiSurfaceHarness();
      final gate = Completer<http.Response>();
      final coverage = UsageSummaryClient(httpClient: MockClient((request) => gate.future));

      AiFeatureHostDependencies dependencies({required bool administrator}) => AiFeatureHostDependencies(
        availabilityReader: harness.availabilityReader,
        reachabilityPort: harness.reachabilityPort,
        sdk: harness.sdk,
        contextProvider: harness.contextProvider,
        manifestRefreshPort: harness.manifestRefreshPort,
        visitId: testVisitId,
        networkSpy: harness.networkSpy,
        persistenceProbe: harness.persistenceProbe,
        exportProbe: harness.exportProbe,
        usageSummaryClient: coverage,
        autoInvoke: false,
        staffIsAdministrator: administrator,
      );

      Widget host({required bool administrator}) => MaterialApp(
        theme: AppTheme.light(),
        home: AiFeatureHostPage(dependencies: dependencies(administrator: administrator)),
      );

      await tester.pumpWidget(host(administrator: true));
      await tester.pumpAndSettle();

      // Role is lost while the administrator coverage read is still pending.
      await tester.pumpWidget(host(administrator: false));
      await tester.pumpAndSettle();

      // The late administrator response must not commit commercial fields.
      gate.complete(_coverageResponse());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai_usage_gauge')), findsNothing);
      expect(find.text('42'), findsNothing);
      expect(find.text('Fixture Plan'), findsNothing);
      expect(find.text('sub-fixture-001'), findsNothing);
    });

    testWidgets('R7-UI1: role promotion loads administrator coverage once', (tester) async {
      final harness = AiSurfaceHarness();
      var coverageCalls = 0;
      final coverage = UsageSummaryClient(
        httpClient: MockClient((request) async {
          coverageCalls++;
          return _coverageResponse();
        }),
      );

      AiFeatureHostDependencies dependencies({required bool administrator}) => AiFeatureHostDependencies(
        availabilityReader: harness.availabilityReader,
        reachabilityPort: harness.reachabilityPort,
        sdk: harness.sdk,
        contextProvider: harness.contextProvider,
        manifestRefreshPort: harness.manifestRefreshPort,
        visitId: testVisitId,
        networkSpy: harness.networkSpy,
        persistenceProbe: harness.persistenceProbe,
        exportProbe: harness.exportProbe,
        usageSummaryClient: coverage,
        autoInvoke: false,
        staffIsAdministrator: administrator,
      );

      Widget host({required bool administrator}) => MaterialApp(
        theme: AppTheme.light(),
        home: AiFeatureHostPage(dependencies: dependencies(administrator: administrator)),
      );

      await tester.pumpWidget(host(administrator: false));
      await tester.pumpAndSettle();
      expect(coverageCalls, 0);
      expect(find.byKey(const Key('ai_usage_gauge')), findsNothing);

      await tester.pumpWidget(host(administrator: true));
      await tester.pumpAndSettle();

      expect(coverageCalls, 1);
      expect(find.byKey(const Key('ai_usage_gauge')), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });
  });
}
