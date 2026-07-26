import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_detail_actions.dart';

InvoiceDetail _issuedInvoice() {
  return InvoiceDetail(
    id: 'inv-1',
    invoiceNumber: 'INV-000001',
    status: InvoiceStatus.issued,
    branchId: 'branch-1',
    patientId: 'patient-1',
    visitId: 'visit-1',
    subtotal: Money.parse('100.00'),
    discountAmount: Money.parse('0.00'),
    insuranceCoveredAmount: Money.parse('0.00'),
    currency: 'USD',
    balance: Money.parse('100.00'),
    createdAt: DateTime.parse('2026-06-01T10:00:00.000Z'),
    updatedAt: DateTime.parse('2026-06-02T12:00:00.000Z'),
    items: const [],
    payments: const [],
    patientDisplayName: 'Ahmed Hassan',
    patientMrn: 'MRN-000042',
  );
}

InvoiceDetail _draftInvoice() {
  return InvoiceDetail(
    id: 'inv-draft',
    invoiceNumber: 'INV-DRAFT-001',
    status: InvoiceStatus.draft,
    branchId: 'branch-1',
    patientId: 'patient-1',
    visitId: 'visit-1',
    subtotal: Money.parse('100.00'),
    discountAmount: Money.parse('0.00'),
    insuranceCoveredAmount: Money.parse('0.00'),
    currency: 'USD',
    balance: Money.parse('100.00'),
    createdAt: DateTime.parse('2026-06-01T10:00:00.000Z'),
    updatedAt: DateTime.parse('2026-06-02T12:00:00.000Z'),
    items: const [],
    payments: const [],
    patientDisplayName: 'Ahmed Hassan',
    patientMrn: 'MRN-000042',
  );
}

InvoiceDetailViewState _viewWithAllPermissions(InvoiceDetail invoice) {
  return InvoiceDetailViewState(
    invoice: invoice,
    canCreate: true,
    canApplyDiscount: true,
    canVoid: true,
    canRecordPayment: true,
    canRefund: true,
  );
}

void main() {
  testWidgets('overflow menu keeps billing actions after patient/visit removal', (
    tester,
  ) async {
    final invoice = _issuedInvoice();
    final view = _viewWithAllPermissions(invoice);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: InvoiceDetailActions(
            invoice: invoice,
            view: view,
            onEdit: () {},
            onVoid: () {},
            onRecordPayment: () {},
            onRecordRefund: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Invoice actions'));
    await tester.pumpAndSettle();

    expect(find.text('Void'), findsOneWidget);
    expect(find.text('Record payment'), findsOneWidget);
    expect(find.text('View patient profile'), findsNothing);
    expect(find.text('View visit'), findsNothing);
  });

  testWidgets('overflow menu shows edit draft for draft invoices', (
    tester,
  ) async {
    final invoice = _draftInvoice();
    final view = _viewWithAllPermissions(invoice);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: InvoiceDetailActions(
            invoice: invoice,
            view: view,
            onEdit: () {},
            onVoid: () {},
            onRecordPayment: () {},
            onRecordRefund: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Invoice actions'));
    await tester.pumpAndSettle();

    expect(find.text('Edit draft'), findsOneWidget);
    expect(find.text('View patient profile'), findsNothing);
    expect(find.text('View visit'), findsNothing);
  });
}
