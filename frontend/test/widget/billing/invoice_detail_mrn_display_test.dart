import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_hero_card.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_link_card.dart';

InvoiceDetail _invoiceDetail({String? patientMrn}) {
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
    patientMrn: patientMrn,
    patientPhone: '+20 100 000 0000',
  );
}

void main() {
  testWidgets('InvoiceHeroCard renders patient MRN alongside billed-to line (US5)', (tester) async {
    const mrn = 'MRN-000042';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: InvoiceHeroCard(
            invoice: _invoiceDetail(patientMrn: mrn),
            patientName: 'Ahmed Hassan',
            balance: Money.parse('100.00'),
            mrn: mrn,
            onPatientTap: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Billed to'), findsOneWidget);
    expect(find.textContaining('· $mrn'), findsOneWidget);
  });

  testWidgets('InvoiceLinkCard renders patient MRN in subtitle (US5)', (tester) async {
    const mrn = 'MRN-000042';
    const phone = '+20 100 000 0000';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: InvoiceLinkCard(
            eyebrow: 'Patient',
            icon: Icons.person_outline,
            title: 'Ahmed Hassan',
            subtitle: '$mrn · $phone',
            actionLabel: 'View',
            onAction: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('$mrn · $phone'), findsOneWidget);
  });
}
