import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BillingFormatting.formatMoney', () {
    test('formats known currency symbols', () {
      expect(BillingFormatting.formatMoney(Money.parse('12.50'), currency: 'USD'), '\$12.50');
      expect(BillingFormatting.formatMoney(Money.parse('12.50'), currency: 'EUR'), '€12.50');
      expect(BillingFormatting.formatMoney(Money.parse('12.50'), currency: 'GBP'), '£12.50');
      expect(BillingFormatting.formatMoney(Money.parse('12.50'), currency: 'EGP'), 'E£ 12.50');
    });

    test('uses currency name path for unknown codes', () {
      final formatted = BillingFormatting.formatMoney(Money.parse('12.50'), currency: 'chf');

      expect(formatted, contains('12.50'));
      expect(formatted.toUpperCase(), contains('CHF'));
    });

    test('formats zero and negative amounts', () {
      expect(BillingFormatting.formatMoney(Money.parse('0'), currency: 'USD'), '\$0.00');
      expect(BillingFormatting.formatMoney(Money.parse('-4.25'), currency: 'USD'), '-\$4.25');
    });

    test('falls back to symbol plus wire value when formatting fails', () {
      final formatted = BillingFormatting.formatMoney(
        Money.parse('9.99'),
        currency: 'USD',
        locale: 'invalid_locale_for_tests',
      );

      expect(formatted, '\$9.99');
    });

    test('falls back to wire value plus currency when formatting fails without a symbol', () {
      final formatted = BillingFormatting.formatMoney(
        Money.parse('9.99'),
        currency: 'JPY',
        locale: 'invalid_locale_for_tests',
      );

      expect(formatted, '9.99 JPY');
    });
  });

  group('BillingFormatting date helpers', () {
    test('formatDate uses MMM d, yyyy in local time', () {
      final utc = DateTime.utc(2026, 6, 15, 14, 30);
      expect(BillingFormatting.formatDate(utc), BillingFormatting.formatDate(utc.toLocal()));
      expect(BillingFormatting.formatDate(utc), matches(RegExp(r'^[A-Z][a-z]{2} \d{1,2}, \d{4}$')));
    });

    test('formatDateTime uses MMM d, yyyy · h:mm a in local time', () {
      final utc = DateTime.utc(2026, 6, 15, 14, 30);
      expect(BillingFormatting.formatDateTime(utc), BillingFormatting.formatDateTime(utc.toLocal()));
      expect(
        BillingFormatting.formatDateTime(utc),
        matches(RegExp(r'^[A-Z][a-z]{2} \d{1,2}, \d{4} · \d{1,2}:\d{2} (AM|PM)$')),
      );
    });
  });

  group('BillingFormatting.invoiceDisplayNumber', () {
    const invoiceId = '11111111-1111-4111-8111-111111111111';

    test('returns trimmed invoice numbers as-is', () {
      expect(BillingFormatting.invoiceDisplayNumber('  INV-MAIN-000001  ', invoiceId), 'INV-MAIN-000001');
    });

    test('falls back to draft prefix with first eight id chars', () {
      expect(BillingFormatting.invoiceDisplayNumber(null, invoiceId), 'Draft · 11111111');
      expect(BillingFormatting.invoiceDisplayNumber('', invoiceId), 'Draft · 11111111');
      expect(BillingFormatting.invoiceDisplayNumber('   ', invoiceId), 'Draft · 11111111');
    });
  });

  group('BillingFormatting.discountLabel', () {
    test('returns em dash for missing or invalid values', () {
      expect(BillingFormatting.discountLabel(null, '10'), '—');
      expect(BillingFormatting.discountLabel(DiscountKind.percentage, null), '—');
      expect(BillingFormatting.discountLabel(DiscountKind.fixed, '   '), '—');
      expect(BillingFormatting.discountLabel(DiscountKind.percentage, 'abc'), '—');
    });

    test('formats percentage discounts as rounded integers', () {
      expect(BillingFormatting.discountLabel(DiscountKind.percentage, '10.6'), '11% off');
      expect(BillingFormatting.discountLabel(DiscountKind.percentage, '0'), '0% off');
    });

    test('formats fixed discounts to two decimals', () {
      expect(BillingFormatting.discountLabel(DiscountKind.fixed, '25'), '25.00 off');
      expect(BillingFormatting.discountLabel(DiscountKind.fixed, '12.5'), '12.50 off');
    });
  });

  group('statusBadgeStyle', () {
    test('maps every invoice status to variant and icon identity', () {
      final styles = {
        InvoiceStatus.draft: statusBadgeStyle(InvoiceStatus.draft),
        InvoiceStatus.issued: statusBadgeStyle(InvoiceStatus.issued),
        InvoiceStatus.partiallyPaid: statusBadgeStyle(InvoiceStatus.partiallyPaid),
        InvoiceStatus.paid: statusBadgeStyle(InvoiceStatus.paid),
        InvoiceStatus.voided: statusBadgeStyle(InvoiceStatus.voided),
      };

      expect(styles[InvoiceStatus.draft]!.variant, InvoiceStatusBadgeVariant.muted);
      expect(styles[InvoiceStatus.draft]!.icon, Icons.edit_note_outlined);

      expect(styles[InvoiceStatus.issued]!.variant, InvoiceStatusBadgeVariant.primary);
      expect(styles[InvoiceStatus.issued]!.icon, Icons.receipt_long_outlined);

      expect(styles[InvoiceStatus.partiallyPaid]!.variant, InvoiceStatusBadgeVariant.accent);
      expect(styles[InvoiceStatus.partiallyPaid]!.icon, Icons.payments_outlined);

      expect(styles[InvoiceStatus.paid]!.variant, InvoiceStatusBadgeVariant.success);
      expect(styles[InvoiceStatus.paid]!.icon, Icons.check_circle_outline);

      expect(styles[InvoiceStatus.voided]!.variant, InvoiceStatusBadgeVariant.destructive);
      expect(styles[InvoiceStatus.voided]!.icon, Icons.block_outlined);
    });
  });

  group('BillingFormatting.paymentMethodIcon', () {
    test('maps every payment method to its icon identity', () {
      expect(BillingFormatting.paymentMethodIcon(PaymentMethod.cash), Icons.payments_outlined);
      expect(BillingFormatting.paymentMethodIcon(PaymentMethod.card), Icons.credit_card_outlined);
      expect(BillingFormatting.paymentMethodIcon(PaymentMethod.bankTransfer), Icons.account_balance_outlined);
      expect(
        BillingFormatting.paymentMethodIcon(PaymentMethod.insuranceSettlement),
        Icons.health_and_safety_outlined,
      );
    });
  });
}
