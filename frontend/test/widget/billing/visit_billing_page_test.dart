import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/billing/presentation/pages/visit_billing_page.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_billing_flow.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

import '../../support/visit_encounter_test_support.dart';
import 'billing_widget_test_harness.dart';

void main() {
  group('VisitBillingPage', () {
    testWidgets('shows visit documentation loading state', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const VisitBillingPage(visitId: billingTestVisitId),
        overrides: billingProviderOverrides(
          visitId: billingTestVisitId,
          extraOverrides: [
            visitDocumentationProvider(billingTestVisitId).overrideWith(
              () => _LoadingVisitDocumentationNotifier(),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows visit documentation error state', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const VisitBillingPage(visitId: billingTestVisitId),
        overrides: billingProviderOverrides(
          visitId: billingTestVisitId,
          visitDocError: Exception('documentation failed'),
        ),
      );
      await pumpBillingFrames(tester);

      expect(find.text('Exception: documentation failed'), findsOneWidget);
    });

    testWidgets('success renders header and VisitBillingFlow', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const VisitBillingPage(visitId: billingTestVisitId),
        overrides: billingProviderOverrides(
          visitId: billingTestVisitId,
          visitDocState: sampleEncounterDocState(),
        ),
      );
      await pumpBillingFrames(tester);

      expect(find.text('Bill this visit'), findsOneWidget);
      expect(find.byType(VisitBillingFlow), findsOneWidget);
    });

    testWidgets('beginBilling invoked on first frame', (tester) async {
      final flowNotifier = SpyVisitBillingFlowNotifier(billingTestVisitId);

      await pumpBillingSurface(
        tester,
        child: const VisitBillingPage(visitId: billingTestVisitId),
        overrides: billingProviderOverrides(
          visitId: billingTestVisitId,
          visitDocState: sampleEncounterDocState(),
          visitBillingFlowNotifier: flowNotifier,
        ),
      );
      await tester.pump();

      expect(flowNotifier.beginBillingCallCount, 1);
    });

    testWidgets('back-to-review navigates to visit document route', (tester) async {
      await pumpBillingRouter(
        tester,
        home: const SizedBox.shrink(),
        initialLocation: AppRoutes.billingVisit(billingTestVisitId),
        overrides: billingProviderOverrides(
          visitId: billingTestVisitId,
          visitDocState: sampleEncounterDocState(),
        ),
        visitBillingBuilder: (context, state) => VisitBillingPage(
          visitId: state.pathParameters['visitId']!,
        ),
      );
      await pumpBillingFrames(tester);

      await tester.tap(find.text('Back to review'));
      await pumpBillingFrames(tester);

      expect(find.text('stub:visit-document-$billingTestVisitId'), findsOneWidget);
    });

    testWidgets('completion navigates to billing invoices route', (tester) async {
      await pumpBillingRouter(
        tester,
        home: const Scaffold(body: Text('Invoices ledger')),
        initialLocation: AppRoutes.billingVisit(billingTestVisitId),
        overrides: billingProviderOverrides(
          visitId: billingTestVisitId,
          visitDocState: sampleEncounterDocState(),
        ),
        visitBillingBuilder: (context, state) => VisitBillingPage(
          visitId: state.pathParameters['visitId']!,
        ),
      );
      await pumpBillingFrames(tester);

      final flow = tester.widget<VisitBillingFlow>(find.byType(VisitBillingFlow));
      flow.onCompleted?.call();
      await pumpBillingFrames(tester);

      expect(find.text('Invoices ledger'), findsOneWidget);
    });
  });
}

class _LoadingVisitDocumentationNotifier extends VisitDocumentationNotifier {
  @override
  Future<VisitDocumentationState> build() async {
    return Completer<VisitDocumentationState>().future;
  }
}
