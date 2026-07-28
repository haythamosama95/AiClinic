import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_hero_card.dart';

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

void main() {
  testWidgets('InvoiceHeroCard shows Void and Print buttons', (tester) async {
    var voidTapped = false;
    var printTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: InvoiceHeroCard(
            invoice: _issuedInvoice(),
            patientName: 'Ahmed Hassan',
            balance: Money.parse('100.00'),
            onPatientTap: () {},
            canVoid: true,
            onVoid: () => voidTapped = true,
            onPrint: () => printTapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Void'), findsOneWidget);
    expect(find.text('Print'), findsOneWidget);
    expect(find.bySemanticsLabel('Invoice actions'), findsNothing);

    await tester.tap(find.text('Void'));
    await tester.tap(find.text('Print'));
    await tester.pump();

    expect(voidTapped, isTrue);
    expect(printTapped, isTrue);
  });

  testWidgets('InvoiceHeroCard disables Void when invoice is not voidable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: InvoiceHeroCard(
            invoice: _issuedInvoice().copyWithStatus(InvoiceStatus.paid),
            patientName: 'Ahmed Hassan',
            balance: Money.zero,
            onPatientTap: () {},
            canVoid: false,
            onVoid: () {},
            onPrint: () {},
          ),
        ),
      ),
    );

    final buttons = tester.widgetList<AppButton>(find.byType(AppButton));
    final voidButton = buttons.firstWhere((button) => button.child is Text && (button.child as Text).data == 'Void');
    expect(voidButton.disabled, isTrue);
  });
}

extension on InvoiceDetail {
  InvoiceDetail copyWithStatus(InvoiceStatus status) {
    return InvoiceDetail(
      id: id,
      invoiceNumber: invoiceNumber,
      status: status,
      branchId: branchId,
      patientId: patientId,
      visitId: visitId,
      subtotal: subtotal,
      discountAmount: discountAmount,
      insuranceCoveredAmount: insuranceCoveredAmount,
      currency: currency,
      balance: balance,
      createdAt: createdAt,
      updatedAt: updatedAt,
      items: items,
      payments: payments,
      patientDisplayName: patientDisplayName,
      patientMrn: patientMrn,
    );
  }
}
