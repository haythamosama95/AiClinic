import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/domain/payment.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_detail_tooltip.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_line_items_card.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_link_card.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_meta_grid.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_payments_card.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_section_title.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_totals_panel.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_detail/invoice_voided_notice.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_perforation_divider.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

InvoiceItem _lineItem() {
  return InvoiceItem(
    id: 'item-1',
    description: 'Consultation',
    quantity: '1',
    unitPrice: Money.parse('100.00'),
    lineSubtotal: Money.parse('100.00'),
    lineDiscountAmount: Money.zero,
    lineTotal: Money.parse('100.00'),
  );
}

Payment _payment({bool refund = false}) {
  return Payment(
    id: 'pay-1',
    method: PaymentMethod.card,
    amount: refund ? Money.parse('-25.00') : Money.parse('50.00'),
    recordedById: 'staff-1',
    recordedByDisplayName: 'Reception',
    recordedAt: DateTime.parse('2026-06-02T14:30:00.000Z'),
    note: 'Front desk',
  );
}

InvoiceDetail _voidedInvoice() {
  final voidedAt = DateTime.parse('2026-06-03T09:15:00.000Z');
  return InvoiceDetail(
    id: 'inv-voided',
    invoiceNumber: 'INV-VOID-001',
    status: InvoiceStatus.voided,
    branchId: 'branch-1',
    patientId: 'patient-1',
    visitId: 'visit-1',
    subtotal: Money.parse('100.00'),
    discountAmount: Money.zero,
    insuranceCoveredAmount: Money.zero,
    currency: 'USD',
    balance: Money.zero,
    createdAt: DateTime.parse('2026-06-01T10:00:00.000Z'),
    updatedAt: voidedAt,
    voidedAt: voidedAt,
    voidReason: 'Entered in error',
    voidedByName: 'Admin User',
    items: const [],
    payments: const [],
  );
}

Future<void> _pumpWide(
  WidgetTester tester,
  Widget child, {
  bool withL10n = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: withL10n ? AppLocalizations.localizationsDelegates : null,
      supportedLocales: withL10n ? AppLocalizations.supportedLocales : const [Locale('en')],
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('InvoiceLineItemsCard', () {
    final totals = InvoiceTotalsModel.lineItems(
      subtotal: Money.parse('100.00'),
      discountAmount: Money.zero,
      insuranceCoveredAmount: Money.zero,
      amountDue: Money.parse('100.00'),
      currency: 'USD',
    );

    testWidgets('renders line item rows', (tester) async {
      await _pumpWide(
        tester,
        InvoiceLineItemsCard(
          items: [_lineItem()],
          currency: 'USD',
          totals: totals,
        ),
      );

      expect(find.text('Consultation'), findsOneWidget);
      expect(find.text('SERVICE'), findsOneWidget);
      expect(find.text('AMOUNT'), findsOneWidget);
    });

    testWidgets('renders No line items empty state', (tester) async {
      await _pumpWide(
        tester,
        InvoiceLineItemsCard(
          items: const [],
          currency: 'USD',
          totals: totals,
        ),
      );

      expect(find.text('No line items'), findsOneWidget);
    });
  });

  group('InvoicePaymentsCard', () {
    final totals = InvoiceTotalsModel.payments(
      amountDue: Money.parse('100.00'),
      netPaid: Money.parse('50.00'),
      balance: Money.parse('50.00'),
      currency: 'USD',
      isVoided: false,
      hasPayments: true,
    );

    testWidgets('renders payment rows', (tester) async {
      await _pumpWide(
        tester,
        InvoicePaymentsCard(
          payments: [_payment()],
          currency: 'USD',
          status: InvoiceStatus.issued,
          totals: totals,
        ),
        withL10n: true,
      );

      expect(find.text('Card'), findsOneWidget);
      expect(find.text('Front desk'), findsOneWidget);
      expect(find.text('Reception'), findsOneWidget);
    });

    testWidgets('marks a refund in the payment row', (tester) async {
      await _pumpWide(
        tester,
        InvoicePaymentsCard(
          payments: [_payment(refund: true)],
          currency: 'USD',
          status: InvoiceStatus.partiallyPaid,
          totals: totals,
        ),
        withL10n: true,
      );

      expect(find.textContaining('Refund'), findsOneWidget);
    });

    testWidgets('renders No payments yet empty state', (tester) async {
      await _pumpWide(
        tester,
        InvoicePaymentsCard(
          payments: const [],
          currency: 'USD',
          status: InvoiceStatus.issued,
          totals: InvoiceTotalsModel.payments(
            amountDue: Money.parse('100.00'),
            netPaid: Money.zero,
            balance: Money.parse('100.00'),
            currency: 'USD',
            isVoided: false,
            hasPayments: false,
          ),
        ),
      );

      expect(find.text('No payments yet'), findsOneWidget);
      expect(
        find.text('Payments recorded against this invoice will appear here.'),
        findsOneWidget,
      );
    });

    testWidgets('renders draft-specific empty state copy', (tester) async {
      await _pumpWide(
        tester,
        InvoicePaymentsCard(
          payments: const [],
          currency: 'USD',
          status: InvoiceStatus.draft,
          totals: InvoiceTotalsModel.payments(
            amountDue: Money.parse('100.00'),
            netPaid: Money.zero,
            balance: Money.parse('100.00'),
            currency: 'USD',
            isVoided: false,
            hasPayments: false,
          ),
        ),
      );

      expect(find.text('No payments yet'), findsOneWidget);
      expect(find.text('Issue this invoice before recording a payment.'), findsOneWidget);
    });
  });

  group('InvoiceTotalsPanel', () {
    testWidgets('renders subtotal, discount, insurance, and balance rows', (tester) async {
      await _pumpWide(
        tester,
        InvoiceTotalsPanel(
          model: InvoiceTotalsModel.lineItems(
            subtotal: Money.parse('100.00'),
            discountAmount: Money.parse('10.00'),
            discountKind: DiscountKind.percentage,
            discountValue: '10',
            insuranceCoveredAmount: Money.parse('20.00'),
            insuranceProviderName: 'Acme Insurance',
            amountDue: Money.parse('70.00'),
            currency: 'USD',
          ),
        ),
      );

      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.textContaining('Invoice discount'), findsOneWidget);
      expect(find.textContaining('Insurance covered'), findsOneWidget);
      expect(find.text('Amount due'), findsOneWidget);
    });

    testWidgets('omits zero discount and insurance rows', (tester) async {
      await _pumpWide(
        tester,
        InvoiceTotalsPanel(
          model: InvoiceTotalsModel.lineItems(
            subtotal: Money.parse('100.00'),
            discountAmount: Money.zero,
            insuranceCoveredAmount: Money.zero,
            amountDue: Money.parse('100.00'),
            currency: 'USD',
          ),
        ),
      );

      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.textContaining('Invoice discount'), findsNothing);
      expect(find.textContaining('Insurance covered'), findsNothing);
      expect(find.text('Amount due'), findsOneWidget);
    });
  });

  testWidgets('InvoiceVoidedNotice renders reason and audit line', (tester) async {
    final invoice = _voidedInvoice();
    final auditLine = '${BillingFormatting.formatDateTime(invoice.voidedAt!)} · Admin User';

    await _pumpWide(tester, InvoiceVoidedNotice(invoice: invoice));

    expect(find.text('This invoice was voided'), findsOneWidget);
    expect(find.text('Entered in error'), findsOneWidget);
    expect(find.text(auditLine), findsOneWidget);
  });

  testWidgets('InvoiceLinkCard invokes onAction', (tester) async {
    var tapped = false;

    await _pumpWide(
      tester,
      InvoiceLinkCard(
        eyebrow: 'Patient',
        icon: Icons.person_outline,
        title: 'Ahmed Hassan',
        subtitle: 'MRN-000042',
        actionLabel: 'View patient',
        onAction: () => tapped = true,
      ),
    );

    await tester.tap(find.bySemanticsLabel('View patient'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('InvoiceMetaGrid renders badges including Not yet issued warning', (tester) async {
    await _pumpWide(
      tester,
      InvoiceMetaGrid(
        items: [
          const InvoiceMetaItem(label: 'Issued', value: 'Not yet issued'),
          const InvoiceMetaItem(label: 'Branch', value: 'Main'),
        ],
      ),
    );

    expect(find.textContaining('Issued'), findsOneWidget);
    expect(find.textContaining('Not yet issued'), findsOneWidget);
    expect(find.textContaining('Branch'), findsOneWidget);

    final warningBadge = tester.widget<AppBadge>(find.byType(AppBadge).first);
    expect(warningBadge.color, BadgeColor.warning);
  });

  testWidgets('InvoiceSectionTitle renders its title', (tester) async {
    await _pumpWide(
      tester,
      const InvoiceSectionTitle(icon: Icons.receipt_long_outlined, title: 'Line items'),
    );

    expect(find.text('Line items'), findsOneWidget);
  });

  testWidgets('InvoiceDetailTooltip wraps child in Tooltip with message', (tester) async {
    await _pumpWide(
      tester,
      InvoiceDetailTooltip(
        message: 'Tooltip copy',
        child: const Text('Child'),
      ),
    );

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'Tooltip copy');
    expect(find.text('Child'), findsOneWidget);
  });

  testWidgets('InvoicePerforationDivider builds', (tester) async {
    await _pumpWide(tester, const InvoicePerforationDivider());

    expect(find.byType(InvoicePerforationDivider), findsOneWidget);
  });
}
