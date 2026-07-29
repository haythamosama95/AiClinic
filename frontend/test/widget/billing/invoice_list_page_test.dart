import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_pagination.dart';
import 'package:ai_clinic/core/ui/components/app_skeleton.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_controls.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_filters.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_list_page.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_list_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_list_controls.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_table.dart';

import 'billing_widget_test_harness.dart';

class RetryableErrorInvoiceListNotifier extends InvoiceListNotifier {
  var buildCount = 0;

  @override
  Future<InvoiceListUiState> build() async {
    buildCount++;
    if (buildCount == 1) {
      throw Exception('load failed');
    }
    return buildBillingListState();
  }
}

void main() {
  group('InvoiceListPage', () {
    testWidgets('builds successfully', (tester) async {
      final notifier = SpyInvoiceListNotifier(buildBillingListState());

      await pumpBillingSurface(
        tester,
        child: const InvoiceListPage(),
        overrides: billingProviderOverrides(listNotifier: notifier),
      );
      await pumpBillingFrames(tester);

      expect(find.text('Invoices'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows loading skeleton while provider is loading', (tester) async {
      await pumpBillingSurface(
        tester,
        child: const InvoiceListPage(),
        overrides: billingProviderOverrides(
          invoiceListOverride: invoiceListProvider.overrideWith(
            () => LoadingInvoiceListNotifier(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AppSkeleton), findsWidgets);
      expect(find.byType(InvoiceLedgerTable), findsOneWidget);
    });

    testWidgets('shows error state with Retry that re-triggers provider', (tester) async {
      final notifier = RetryableErrorInvoiceListNotifier();

      await pumpBillingSurface(
        tester,
        child: const InvoiceListPage(),
        overrides: billingProviderOverrides(
          invoiceListOverride: invoiceListProvider.overrideWith(() => notifier),
        ),
      );
      await pumpBillingFrames(tester);

      expect(find.text('Could not load invoices'), findsOneWidget);
      expect(notifier.buildCount, 1);

      await tester.tap(find.text('Retry'));
      await pumpBillingFrames(tester);
      await pumpBillingFrames(tester);

      expect(notifier.buildCount, greaterThan(1));
      expect(find.text('Test Patient'), findsOneWidget);
    });

    testWidgets('shows first-run empty state', (tester) async {
      final notifier = SpyInvoiceListNotifier(
        buildBillingListState(
          items: const [],
          hasInvoices: false,
          estimatedTotal: 0,
        ),
      );

      await pumpBillingSurface(
        tester,
        child: const InvoiceListPage(),
        overrides: billingProviderOverrides(listNotifier: notifier),
      );
      await pumpBillingFrames(tester);

      expect(find.text('No invoices yet'), findsOneWidget);
      expect(find.byType(InvoiceListControlsBar), findsNothing);
    });

    testWidgets('shows filtered-empty state with working Clear filters', (tester) async {
      final notifier = SpyInvoiceListNotifier(
        buildBillingListState(
          items: const [],
          hasInvoices: true,
          filters: const InvoiceListFilters(patientSearch: 'no-match'),
          estimatedTotal: 0,
        ),
      );

      await pumpBillingSurface(
        tester,
        child: const InvoiceListPage(),
        overrides: billingProviderOverrides(listNotifier: notifier),
      );
      await pumpBillingFrames(tester);

      expect(find.text('No invoices match'), findsOneWidget);
      expect(find.byType(InvoiceListControlsBar), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await pumpBillingFrames(tester);

      expect(notifier.applyControlsCallCount, 1);
      expect(notifier.lastAppliedControls, InvoiceListControls.defaultControls);
    });

    testWidgets('shows controls bar only when invoices exist', (tester) async {
      final emptyNotifier = SpyInvoiceListNotifier(
        buildBillingListState(items: const [], hasInvoices: false, estimatedTotal: 0),
      );

      await pumpBillingSurface(
        tester,
        child: const InvoiceListPage(),
        overrides: billingProviderOverrides(listNotifier: emptyNotifier),
      );
      await pumpBillingFrames(tester);
      expect(find.byType(InvoiceListControlsBar), findsNothing);

      final populatedNotifier = SpyInvoiceListNotifier(buildBillingListState());
      await pumpBillingSurface(
        tester,
        child: const InvoiceListPage(),
        overrides: billingProviderOverrides(listNotifier: populatedNotifier),
      );
      await pumpBillingFrames(tester);
      expect(find.byType(InvoiceListControlsBar), findsOneWidget);
    });

    testWidgets('renders populated rows and pagination', (tester) async {
      final notifier = SpyInvoiceListNotifier(
        buildBillingListState(
          items: [
            buildBillingInvoiceListItem(),
            buildBillingInvoiceListItem(
              id: '55555555-5555-4555-8555-555555555555',
              invoiceNumber: 'INV-MAIN-000002',
            ),
          ],
          hasMore: true,
          estimatedTotal: 3,
        ),
      );

      await pumpBillingSurface(
        tester,
        child: const InvoiceListPage(),
        overrides: billingProviderOverrides(listNotifier: notifier),
      );
      await pumpBillingFrames(tester);

      expect(find.text('Test Patient'), findsWidgets);
      expect(find.text('INV-MAIN-000001'), findsOneWidget);
      expect(find.byType(AppPagination), findsOneWidget);
    });

    testWidgets('row tap navigates to invoice detail route', (tester) async {
      final notifier = SpyInvoiceListNotifier(buildBillingListState());

      await pumpBillingRouter(
        tester,
        home: const InvoiceListPage(),
        overrides: billingProviderOverrides(listNotifier: notifier),
      );
      await pumpBillingFrames(tester);

      await tester.tap(find.text('INV-MAIN-000001'));
      await pumpBillingFrames(tester);

      expect(
        find.text('stub:invoice-detail-$billingTestIssuedInvoiceId'),
        findsOneWidget,
      );
    });

    testWidgets('pagination page change calls applyControls', (tester) async {
      final notifier = SpyInvoiceListNotifier(
        buildBillingListState(
          hasMore: true,
          estimatedTotal: 25,
          filters: const InvoiceListFilters(pageSize: 10),
        ),
      );

      await pumpBillingSurface(
        tester,
        child: const InvoiceListPage(),
        overrides: billingProviderOverrides(listNotifier: notifier),
      );
      await pumpBillingFrames(tester);

      await tester.tap(find.bySemanticsLabel('Next page'));
      await pumpBillingFrames(tester);

      expect(notifier.applyControlsCallCount, 1);
      expect(notifier.lastAppliedControls?.page, 2);
    });

    testWidgets('reload fires on first frame', (tester) async {
      final notifier = SpyInvoiceListNotifier(buildBillingListState());

      await pumpBillingSurface(
        tester,
        child: const InvoiceListPage(),
        overrides: billingProviderOverrides(listNotifier: notifier),
      );
      await tester.pump();

      expect(notifier.reloadCallCount, 1);
    });
  });
}
