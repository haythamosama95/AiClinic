import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/money/money.dart';
import 'package:ai_clinic/core/money/money_formatter.dart';
import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';

/// Presentation helpers for billing amounts and dates (V1-6).
abstract final class BillingFormatting {
  static final _dateFormat = DateFormat('MMM d, yyyy');
  static final _dateTimeFormat = DateFormat('MMM d, yyyy · h:mm a');

  static String formatDate(DateTime date) => _dateFormat.format(date.toLocal());

  static String formatDateTime(DateTime date) => _dateTimeFormat.format(date.toLocal());

  static String invoiceDisplayNumber(String? invoiceNumber, String invoiceId) {
    final number = invoiceNumber?.trim();
    if (number != null && number.isNotEmpty) {
      return number;
    }
    return 'Draft · ${invoiceId.substring(0, 8)}';
  }

  static IconData paymentMethodIcon(PaymentMethod method) {
    return switch (method) {
      PaymentMethod.cash => Icons.payments_outlined,
      PaymentMethod.card => Icons.credit_card_outlined,
      PaymentMethod.bankTransfer => Icons.account_balance_outlined,
      PaymentMethod.insuranceSettlement => Icons.health_and_safety_outlined,
    };
  }

  static String discountLabel(DiscountKind? kind, String? value, {required String currency}) {
    if (kind == null) {
      return '';
    }

    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return '';
    }

    return switch (kind) {
      DiscountKind.percentage => () {
        final parsed = Decimal.tryParse(trimmed);
        final display = parsed?.toString() ?? trimmed;
        return '${_trimTrailingZero(display)}% off';
      }(),
      DiscountKind.fixed => '${MoneyFormatter.format(Money.parse(trimmed), currency: currency)} off',
    };
  }

  static String _trimTrailingZero(String value) {
    if (!value.contains('.')) {
      return value;
    }
    return value.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

/// Maps invoice status to semantic badge styling.
InvoiceStatusBadgeStyle statusBadgeStyle(InvoiceStatus status) {
  return switch (status) {
    InvoiceStatus.draft => const InvoiceStatusBadgeStyle(
      variant: InvoiceStatusBadgeVariant.muted,
      icon: Icons.edit_note_outlined,
    ),
    InvoiceStatus.issued => const InvoiceStatusBadgeStyle(
      variant: InvoiceStatusBadgeVariant.primary,
      icon: Icons.receipt_long_outlined,
    ),
    InvoiceStatus.partiallyPaid => const InvoiceStatusBadgeStyle(
      variant: InvoiceStatusBadgeVariant.accent,
      icon: Icons.payments_outlined,
    ),
    InvoiceStatus.paid => const InvoiceStatusBadgeStyle(
      variant: InvoiceStatusBadgeVariant.success,
      icon: Icons.check_circle_outline,
    ),
    InvoiceStatus.voided => const InvoiceStatusBadgeStyle(
      variant: InvoiceStatusBadgeVariant.destructive,
      icon: Icons.block_outlined,
    ),
  };
}

enum InvoiceStatusBadgeVariant { muted, primary, accent, success, destructive }

class InvoiceStatusBadgeStyle {
  const InvoiceStatusBadgeStyle({required this.variant, required this.icon});

  final InvoiceStatusBadgeVariant variant;
  final IconData icon;
}
