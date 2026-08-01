import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_row_context_menu.dart';

import '../../support/billing_rpc_test_client.dart';

InvoiceListItem _row({
  required String id,
  required InvoiceStatus status,
  String? patientId,
}) {
  return InvoiceListItem(
    id: id,
    invoiceNumber: 'INV-000001',
    status: status,
    patientDisplayName: 'Ahmed Hassan',
    patientId: patientId,
    subtotal: Money.parse('100.00'),
    discountAmount: Money.parse('0.00'),
    insuranceCoveredAmount: Money.parse('0.00'),
    paidAmount: Money.parse('0.00'),
    balance: Money.parse('100.00'),
    createdAt: DateTime.parse('2026-06-01T10:00:00.000Z'),
    currency: 'USD',
  );
}

Future<void> _openMenu(
  WidgetTester tester, {
  required Widget home,
}) async {
  await tester.pumpWidget(home);
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel('Row actions'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('InvoiceRowContextMenu reveals Open, View patient, and Void invoice actions', (tester) async {
    final client = BillingRpcTestClient();

    await _openMenu(
      tester,
      home: ProviderScope(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: InvoiceRowContextMenu(
                row: _row(id: 'inv-1', status: InvoiceStatus.issued, patientId: 'patient-1'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Open invoice'), findsOneWidget);
    expect(find.text('View patient'), findsOneWidget);
    expect(find.text('Void invoice'), findsOneWidget);
  });

  testWidgets('InvoiceRowContextMenu disables View patient when patientId is missing', (tester) async {
    final client = BillingRpcTestClient();

    await _openMenu(
      tester,
      home: ProviderScope(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: InvoiceRowContextMenu(
                row: _row(id: 'inv-1', status: InvoiceStatus.issued),
              ),
            ),
          ),
        ),
      ),
    );

    final viewPatient = tester.widget<MenuItemButton>(
      find.ancestor(
        of: find.text('View patient'),
        matching: find.byType(MenuItemButton),
      ),
    );
    expect(viewPatient.onPressed, isNull);
  });

  testWidgets('InvoiceRowContextMenu disables Void invoice when status is not voidable', (tester) async {
    final client = BillingRpcTestClient();

    await _openMenu(
      tester,
      home: ProviderScope(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: InvoiceRowContextMenu(
                row: _row(id: 'inv-1', status: InvoiceStatus.paid, patientId: 'patient-1'),
              ),
            ),
          ),
        ),
      ),
    );

    final voidItem = tester.widget<MenuItemButton>(
      find.ancestor(
        of: find.text('Void invoice'),
        matching: find.byType(MenuItemButton),
      ),
    );
    expect(voidItem.onPressed, isNull);
  });

  testWidgets('InvoiceRowContextMenu Open invoice navigates to invoice detail', (tester) async {
    final client = BillingRpcTestClient();
    final invoiceId = BillingRpcTestClient.issuedInvoiceId;

    await _openMenu(
      tester,
      home: ProviderScope(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: GoRouter(
            initialLocation: '/test',
            routes: [
              GoRoute(
                path: '/test',
<<<<<<< HEAD
                builder: (_, __) => Scaffold(
=======
                builder: (_, _) => Scaffold(
>>>>>>> master
                  body: Center(
                    child: InvoiceRowContextMenu(
                      row: _row(id: invoiceId, status: InvoiceStatus.issued, patientId: 'patient-1'),
                    ),
                  ),
                ),
              ),
              GoRoute(
                path: '/billing/invoices/:id',
                builder: (_, state) => Text('Invoice ${state.pathParameters['id']}'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open invoice'));
    await tester.pumpAndSettle();

    expect(find.text('Invoice $invoiceId'), findsOneWidget);
  });

  testWidgets('InvoiceRowContextMenu View patient navigates to patient detail', (tester) async {
    final client = BillingRpcTestClient();
    const patientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

    await _openMenu(
      tester,
      home: ProviderScope(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: GoRouter(
            initialLocation: '/test',
            routes: [
              GoRoute(
                path: '/test',
<<<<<<< HEAD
                builder: (_, __) => Scaffold(
=======
                builder: (_, _) => Scaffold(
>>>>>>> master
                  body: Center(
                    child: InvoiceRowContextMenu(
                      row: _row(id: 'inv-1', status: InvoiceStatus.issued, patientId: patientId),
                    ),
                  ),
                ),
              ),
              GoRoute(
                path: '/patients/:id',
                builder: (_, state) => Text('Patient ${state.pathParameters['id']}'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('View patient'));
    await tester.pumpAndSettle();

    expect(find.text('Patient $patientId'), findsOneWidget);
  });

  testWidgets('InvoiceRowContextMenu Void invoice opens the void dialog', (tester) async {
    final client = BillingRpcTestClient();

    await _openMenu(
      tester,
      home: ProviderScope(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(InvoiceRepository(client)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: InvoiceRowContextMenu(
                row: _row(
                  id: BillingRpcTestClient.issuedInvoiceId,
                  status: InvoiceStatus.issued,
                  patientId: 'patient-1',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Void invoice'));
    await tester.pumpAndSettle();

    expect(find.text('Void invoice'), findsWidgets);
    expect(
      find.text('This cannot be undone. Payments must be refunded before voiding a paid invoice.'),
      findsOneWidget,
    );
    expect(find.text('Why is this invoice being voided?'), findsOneWidget);
  });
}
