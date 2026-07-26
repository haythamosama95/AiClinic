import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_line_items_card.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_payments_card.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_totals_panel.dart';

void main() {
  final totals = InvoiceTotalsModel.lineItems(
    subtotal: Money.parse('100.00'),
    discountAmount: Money.zero,
    insuranceCoveredAmount: Money.zero,
    amountDue: Money.parse('100.00'),
    currency: 'USD',
  );

  testWidgets('InvoiceLineItemsCard shows enabled Edit invoice when editable', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: InvoiceLineItemsCard(
            items: const [],
            currency: 'USD',
            totals: totals,
            canEdit: true,
            onEdit: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Edit invoice'), findsOneWidget);

    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.disabled, isFalse);

    await tester.tap(find.text('Edit invoice'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('InvoiceLineItemsCard shows disabled Edit invoice when not editable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: InvoiceLineItemsCard(items: const [], currency: 'USD', totals: totals, canEdit: false, onEdit: () {}),
        ),
      ),
    );

    expect(find.text('Edit invoice'), findsOneWidget);

    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.disabled, isTrue);
  });

  testWidgets('InvoicePaymentsCard shows enabled Add payment when allowed', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: InvoicePaymentsCard(
            payments: const [],
            currency: 'USD',
            status: InvoiceStatus.issued,
            canAddPayment: true,
            onAddPayment: () => tapped = true,
            totals: InvoiceTotalsModel.payments(
              amountDue: Money.parse('100.00'),
              netPaid: Money.zero,
              balance: Money.parse('100.00'),
              currency: 'USD',
              isVoided: false,
              hasPayments: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Add payment'), findsOneWidget);

    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.disabled, isFalse);

    await tester.tap(find.text('Add payment'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('InvoicePaymentsCard shows disabled Add payment when not allowed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: InvoicePaymentsCard(
            payments: const [],
            currency: 'USD',
            status: InvoiceStatus.draft,
            canAddPayment: false,
            onAddPayment: () {},
            totals: InvoiceTotalsModel.payments(
              amountDue: Money.parse('100.00'),
              netPaid: Money.zero,
              balance: Money.parse('100.00'),
              currency: 'USD',
              isVoided: false,
              hasPayments: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Add payment'), findsOneWidget);

    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.disabled, isTrue);
  });
}
