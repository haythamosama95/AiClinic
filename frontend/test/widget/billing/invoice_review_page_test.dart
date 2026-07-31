import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_review_page.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_review_step.dart';

import 'billing_widget_test_harness.dart';

void main() {
  group('InvoiceReviewPage', () {
    testWidgets('shows loading spinner', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceReviewPage(invoiceId: billingTestIssuedInvoiceId),
        overrides: billingProviderOverrides(
          extraOverrides: [
            invoiceDetailViewProvider(billingTestIssuedInvoiceId).overrideWithValue(
              const AsyncLoading<InvoiceDetailViewState>(),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error with Retry', (tester) async {
      var loadCount = 0;

      await pumpBillingSurface(
        tester,
        child: const InvoiceReviewPage(invoiceId: billingTestIssuedInvoiceId),
        overrides: billingProviderOverrides(
          extraOverrides: [
            invoiceDetailViewProvider(billingTestIssuedInvoiceId).overrideWith((ref) async {
              loadCount++;
              if (loadCount == 1) {
                throw Exception('detail failed');
              }
              return buildBillingDetailView();
            }),
          ],
        ),
      );
      await pumpBillingFrames(tester);

      expect(find.text('Could not load invoice'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await pumpBillingFrames(tester);
      await pumpBillingFrames(tester);

      expect(loadCount, greaterThan(1));
      expect(find.byType(VisitInvoiceReadOnlyReview), findsOneWidget);
    });

    testWidgets('success shows header metadata', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceReviewPage(invoiceId: billingTestIssuedInvoiceId),
        overrides: billingProviderOverrides(
          detailInvoiceId: billingTestIssuedInvoiceId,
          detailView: buildBillingDetailView(),
        ),
      );
      await pumpBillingFrames(tester);

      expect(find.text('INV-MAIN-000001'), findsNWidgets(2));
      expect(find.textContaining('Test Patient'), findsWidgets);
      expect(find.textContaining('Main'), findsWidgets);
      expect(find.byType(VisitInvoiceReadOnlyReview), findsOneWidget);
      await pumpBillingFrames(tester);
    });

    testWidgets('Back control pops the route', (tester) async {
      final router = await pumpBillingRouter(
        tester,
        home: const Scaffold(body: Text('Previous page')),
        overrides: billingProviderOverrides(
          detailInvoiceId: billingTestIssuedInvoiceId,
          detailView: buildBillingDetailView(),
        ),
        invoiceReviewBuilder: (context, state) => InvoiceReviewPage(
          invoiceId: state.pathParameters['invoiceId']!,
        ),
      );
      await pumpBillingFrames(tester);

      router.push(AppRoutes.billingInvoiceReview(billingTestIssuedInvoiceId));
      await pumpBillingFrames(tester);

      await tester.tap(find.text('Back'));
      await pumpBillingFrames(tester);

      expect(find.text('Previous page'), findsOneWidget);
    });
  });
}
