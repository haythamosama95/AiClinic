import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_detail_page.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_hero_card.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_line_items_card.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_payments_card.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_voided_notice.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/payment_form.dart';

import '../../helpers/role_permission_seed.dart';
import '../../support/billing_rpc_test_client.dart';
import 'billing_widget_test_harness.dart';

void main() {
  group('InvoiceDetailPage', () {
    testWidgets('shows loading spinner', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceDetailPage(invoiceId: billingTestIssuedInvoiceId),
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

    testWidgets('shows not-found view with back control', (tester) async {
      await pumpBillingRouter(
        tester,
        home: const Scaffold(body: Text('Invoices list')),
        initialLocation: AppRoutes.billingInvoiceDetail(billingTestIssuedInvoiceId),
        overrides: billingProviderOverrides(
          detailInvoiceId: billingTestIssuedInvoiceId,
          detailError: billingNotFoundFailure(),
        ),
        invoiceDetailBuilder: (context, state) => InvoiceDetailPage(
          invoiceId: state.pathParameters['invoiceId']!,
        ),
      );
      await pumpBillingFrames(tester);

      expect(find.text('Invoice not found'), findsWidgets);
      expect(find.text('Back to invoices'), findsOneWidget);

      await tester.tap(find.text('Back to invoices'));
      await pumpBillingFrames(tester);

      expect(find.text('Invoices list'), findsOneWidget);
    });

    testWidgets('shows generic error with Retry', (tester) async {
      var loadCount = 0;

      await pumpBillingSurface(
        tester,
        child: const InvoiceDetailPage(invoiceId: billingTestIssuedInvoiceId),
        overrides: billingProviderOverrides(
          extraOverrides: [
            invoiceDetailViewProvider(billingTestIssuedInvoiceId).overrideWith((ref) async {
              loadCount++;
              if (loadCount == 1) {
                throw Exception('network down');
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

      expect(loadCount, greaterThan(1));
      expect(find.byType(InvoiceHeroCard), findsOneWidget);
    });

    testWidgets('success body renders hero, line items, and payments cards', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceDetailPage(invoiceId: billingTestIssuedInvoiceId),
        overrides: billingProviderOverrides(
          detailInvoiceId: billingTestIssuedInvoiceId,
          detailView: buildBillingDetailView(),
        ),
      );
      await pumpBillingFrames(tester);

      expect(find.byType(InvoiceHeroCard), findsOneWidget);
      expect(find.byType(InvoiceLineItemsCard), findsOneWidget);
      expect(find.byType(InvoicePaymentsCard), findsOneWidget);
    });

    testWidgets('voided notice appears only for voided invoice', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceDetailPage(invoiceId: billingTestIssuedInvoiceId),
        overrides: billingProviderOverrides(
          detailInvoiceId: billingTestIssuedInvoiceId,
          detailView: buildBillingDetailView(),
        ),
      );
      await pumpBillingFrames(tester);
      expect(find.byType(InvoiceVoidedNotice), findsNothing);

      await pumpBillingSurface(
        tester,
        child: const InvoiceDetailPage(invoiceId: billingTestIssuedInvoiceId),
        overrides: billingProviderOverrides(
          extraOverrides: [
            invoiceDetailViewProvider(billingTestIssuedInvoiceId).overrideWithValue(
              AsyncData(
                buildBillingDetailView(
                  invoice: buildBillingInvoiceDetail(
                    status: InvoiceStatus.voided,
                    voidReason: 'Entered in error',
                    voidedAt: DateTime.utc(2026, 6, 3),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      await pumpBillingFrames(tester);
      expect(find.text('This invoice was voided'), findsOneWidget);
    });

    testWidgets('breadcrumb navigates back to invoices list', (tester) async {
      final router = await pumpBillingRouter(
        tester,
        home: const Scaffold(body: Text('Invoices list')),
        overrides: billingProviderOverrides(
          detailInvoiceId: billingTestIssuedInvoiceId,
          detailView: buildBillingDetailView(),
        ),
        invoiceDetailBuilder: (context, state) => InvoiceDetailPage(
          invoiceId: state.pathParameters['invoiceId']!,
        ),
      );
      await pumpBillingFrames(tester);

      router.push(AppRoutes.billingInvoiceDetail(billingTestIssuedInvoiceId));
      await pumpBillingFrames(tester);

      await tester.tap(find.text('Invoices').first);
      await pumpBillingFrames(tester);

      expect(find.text('Invoices list'), findsOneWidget);
    });

    testWidgets('patient link navigates to patient route', (tester) async {
      await pumpBillingRouter(
        tester,
        home: const SizedBox.shrink(),
        initialLocation: AppRoutes.billingInvoiceDetail(billingTestIssuedInvoiceId),
        overrides: billingProviderOverrides(
          detailInvoiceId: billingTestIssuedInvoiceId,
          detailView: buildBillingDetailView(),
        ),
        invoiceDetailBuilder: (context, state) => InvoiceDetailPage(
          invoiceId: state.pathParameters['invoiceId']!,
        ),
      );
      await pumpBillingFrames(tester);

      await tester.tap(find.bySemanticsLabel('View patient profile'));
      await pumpBillingFrames(tester);

      expect(find.text('stub:patient-$billingTestPatientId'), findsOneWidget);
    });

    testWidgets('visit link navigates to visit document route', (tester) async {
      await pumpBillingRouter(
        tester,
        home: const SizedBox.shrink(),
        initialLocation: AppRoutes.billingInvoiceDetail(billingTestIssuedInvoiceId),
        overrides: billingProviderOverrides(
          detailInvoiceId: billingTestIssuedInvoiceId,
          detailView: buildBillingDetailView(),
        ),
        invoiceDetailBuilder: (context, state) => InvoiceDetailPage(
          invoiceId: state.pathParameters['invoiceId']!,
        ),
      );
      await pumpBillingFrames(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('View visit in patient record'));
      await pumpBillingFrames(tester);

      expect(find.text('stub:visit-document-$billingTestVisitId'), findsOneWidget);
    });

    testWidgets('Void action opens VoidInvoiceDialog', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceDetailPage(invoiceId: billingTestIssuedInvoiceId),
        overrides: billingProviderOverrides(
          detailInvoiceId: billingTestIssuedInvoiceId,
          detailView: buildBillingDetailView(),
        ),
      );
      await pumpBillingFrames(tester);

      await tester.tap(find.text('Void'));
      await pumpBillingFrames(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Void invoice'), findsWidgets);
    });

    testWidgets('Add payment opens dialog with PaymentForm', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceDetailPage(invoiceId: billingTestIssuedInvoiceId),
        overrides: billingProviderOverrides(
          detailInvoiceId: billingTestIssuedInvoiceId,
          detailView: buildBillingDetailView(),
        ),
      );
      await pumpBillingFrames(tester);

      await tester.tap(find.text('Add payment'));
      await pumpBillingFrames(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(PaymentForm), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Record payment'), findsOneWidget);
    });

    testWidgets('permission-gated actions are disabled without grants', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceDetailPage(invoiceId: billingTestIssuedInvoiceId),
        overrides: billingProviderOverrides(
          auth: billingAuthSession(permissions: RolePermissionSeed.doctor),
          rpcClient: BillingRpcTestClient(),
        ),
      );
      await pumpBillingFrames(tester);

      final buttons = tester.widgetList<AppButton>(find.byType(AppButton));
      final voidButton = buttons.firstWhere(
        (button) => button.child is Text && (button.child as Text).data == 'Void',
      );
      final addPaymentButton = buttons.firstWhere(
        (button) => button.child is Text && (button.child as Text).data == 'Add payment',
      );

      expect(voidButton.disabled, isTrue);
      expect(addPaymentButton.disabled, isTrue);
    });
  });
}
