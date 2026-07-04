import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';

/// Presentation helpers for billing amounts and dates (V1-6).
abstract final class BillingFormatting {
  static String formatMoney(Money amount, {String currency = 'USD'}) {
    final symbol = _currencySymbol(currency);
    final value = amount.wireValue;
    if (symbol != null) {
      return '$symbol$value';
    }
    return '$value $currency';
  }

  static String? _currencySymbol(String currency) {
    return switch (currency.toUpperCase()) {
      'USD' => '\$',
      'EUR' => '€',
      'GBP' => '£',
      'EGP' => 'E£ ',
      _ => null,
    };
  }

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
