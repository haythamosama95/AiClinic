import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_table.dart';

InvoiceListItem _invoiceWithMrn(String? mrn) {
  return InvoiceListItem(
    id: 'inv-1',
    invoiceNumber: 'INV-000001',
    status: InvoiceStatus.issued,
    patientDisplayName: 'Ahmed Hassan',
    patientMrn: mrn,
    subtotal: Money.parse('100.00'),
    discountAmount: Money.parse('0.00'),
    insuranceCoveredAmount: Money.parse('0.00'),
    paidAmount: Money.parse('0.00'),
    balance: Money.parse('100.00'),
    createdAt: DateTime.parse('2026-06-01T10:00:00.000Z'),
    currency: 'USD',
  );
}

void main() {
  testWidgets('InvoiceLedgerTable renders patient MRN in patient cell (US5)', (tester) async {
    const mrn = 'MRN-000042';

    await tester.binding.setSurfaceSize(const Size(1280, 600));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: InvoiceLedgerTable(items: [_invoiceWithMrn(mrn)]),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Ahmed Hassan'), findsOneWidget);
    expect(find.text(mrn), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('InvoiceLedgerTable shows dash when patient MRN is absent (US5)', (tester) async {
    final itemWithoutMrn = _invoiceWithMrn(null);

    await tester.binding.setSurfaceSize(const Size(1280, 600));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: InvoiceLedgerTable(items: [itemWithoutMrn]),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('—'), findsOneWidget);
  });
}
