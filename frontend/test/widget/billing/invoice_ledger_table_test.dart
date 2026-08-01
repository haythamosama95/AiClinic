import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:ai_clinic/core/ui/components/app_skeleton.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_table.dart';

InvoiceListItem _invoice({
  required String id,
  required InvoiceStatus status,
  String? patientDisplayName,
}) {
  return InvoiceListItem(
    id: id,
    invoiceNumber: 'INV-${id.padLeft(6, '0')}',
    status: status,
    patientDisplayName: patientDisplayName,
    subtotal: Money.parse('100.00'),
    discountAmount: Money.parse('0.00'),
    insuranceCoveredAmount: Money.parse('0.00'),
    paidAmount: Money.parse('0.00'),
    balance: Money.parse('100.00'),
    createdAt: DateTime.parse('2026-06-01T10:00:00.000Z'),
    currency: 'USD',
  );
}

Future<void> _pumpLedgerTable(
  WidgetTester tester, {
  required List<InvoiceListItem> items,
  bool loading = false,
  ValueChanged<InvoiceListItem>? onRowClick,
  Widget? emptyState,
  Widget? errorState,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 600));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: InvoiceLedgerTable(
          items: items,
          loading: loading,
          onRowClick: onRowClick,
          emptyState: emptyState,
          errorState: errorState,
        ),
      ),
    ),
  );

  if (loading) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('InvoiceLedgerTable renders all column headers', (tester) async {
    await _pumpLedgerTable(
      tester,
      items: [_invoice(id: 'inv-1', status: InvoiceStatus.issued, patientDisplayName: 'Ahmed Hassan')],
    );

    expect(find.text('Invoice'), findsOneWidget);
    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('Total payments'), findsOneWidget);
    expect(find.text('Remaining'), findsOneWidget);
  });

  testWidgets('InvoiceLedgerTable renders a status badge per row', (tester) async {
    await _pumpLedgerTable(
      tester,
      items: [
        _invoice(id: 'inv-1', status: InvoiceStatus.issued, patientDisplayName: 'Ahmed Hassan'),
        _invoice(id: 'inv-2', status: InvoiceStatus.paid, patientDisplayName: 'Sara Ali'),
      ],
    );

    expect(find.text('Issued'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
  });

  testWidgets('InvoiceLedgerTable shows patient name and Patient fallback when name is missing', (tester) async {
    await _pumpLedgerTable(
      tester,
      items: [
        _invoice(id: 'inv-1', status: InvoiceStatus.issued, patientDisplayName: 'Ahmed Hassan'),
        _invoice(id: 'inv-2', status: InvoiceStatus.issued),
      ],
    );

    expect(find.text('Ahmed Hassan'), findsOneWidget);
    expect(find.text('Patient'), findsNWidgets(2));
  });

  testWidgets('InvoiceLedgerTable loading mode shows skeleton rows', (tester) async {
    await _pumpLedgerTable(tester, items: const [], loading: true);

    expect(find.byType(AppSkeleton), findsWidgets);
    expect(find.byType(SfDataGrid), findsNothing);
  });

  testWidgets('InvoiceLedgerTable renders emptyState when supplied and data is empty', (tester) async {
    await _pumpLedgerTable(
      tester,
      items: const [],
      emptyState: const Text('No invoices yet'),
    );

    expect(find.text('No invoices yet'), findsOneWidget);
  });

  testWidgets('InvoiceLedgerTable renders errorState when supplied', (tester) async {
    await _pumpLedgerTable(
      tester,
      items: [_invoice(id: 'inv-1', status: InvoiceStatus.issued, patientDisplayName: 'Ahmed Hassan')],
      errorState: const Text('Could not load invoices'),
    );

    expect(find.text('Could not load invoices'), findsOneWidget);
  });

  testWidgets('InvoiceLedgerTable row tap invokes onRowClick with the tapped item', (tester) async {
    final item = _invoice(id: 'inv-tap', status: InvoiceStatus.issued, patientDisplayName: 'Ahmed Hassan');
    InvoiceListItem? tapped;

    await _pumpLedgerTable(
      tester,
      items: [item],
      onRowClick: (row) => tapped = row,
    );

    await tester.tap(find.text('Ahmed Hassan'));
    await tester.pump();

    expect(tapped, item);
  });
}
