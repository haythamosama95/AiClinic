import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/domain/payment.dart';
import 'package:flutter/foundation.dart';

/// Summary row from `list_invoices` / `list_patient_invoices` (V1-6).
@immutable
class InvoiceListItem {
  const InvoiceListItem({
    required this.id,
    required this.status,
    required this.subtotal,
    required this.discountAmount,
    required this.insuranceCoveredAmount,
    required this.paidAmount,
    required this.balance,
    required this.createdAt,
    required this.currency,
    this.invoiceNumber,
    this.patientDisplayName,
    this.branchCode,
    this.issuedAt,
    this.payments = const [],
  });

  final String id;
  final String? invoiceNumber;
  final InvoiceStatus status;
  final String? patientDisplayName;
  final String? branchCode;
  final String currency;
  final Money subtotal;
  final Money discountAmount;
  final Money insuranceCoveredAmount;
  final Money paidAmount;
  final Money balance;
  final DateTime createdAt;
  final DateTime? issuedAt;
  final List<Payment> payments;

  /// Subtotal minus invoice-level discount (line discounts are reflected in subtotal server-side).
  String get displayTotal => (subtotal - discountAmount).wireValue;

  static InvoiceListItem? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final status = InvoiceStatus.tryParse(row['status']?.toString());
    final createdAtRaw = row['created_at']?.toString();
    if (id == null || id.isEmpty || status == null || createdAtRaw == null) {
      return null;
    }

    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      return null;
    }

    final subtotal = _parseMoney(row['subtotal']);
    final discountAmount = _parseMoney(row['discount_amount']);
    final insuranceCoveredAmount = _parseMoney(row['insurance_covered_amount']);
    final paidAmount = _parseMoney(row['paid_amount']);
    final balance = _parseMoney(row['balance']);
    if (subtotal == null ||
        discountAmount == null ||
        insuranceCoveredAmount == null ||
        paidAmount == null ||
        balance == null) {
      return null;
    }

    final issuedAtRaw = row['issued_at']?.toString();
    final issuedAt = issuedAtRaw == null ? null : DateTime.tryParse(issuedAtRaw);

    final currency = row['currency']?.toString().trim();
    return InvoiceListItem(
      id: id,
      invoiceNumber: row['invoice_number']?.toString(),
      status: status,
      patientDisplayName: row['patient_display_name']?.toString(),
      branchCode: row['branch_code']?.toString(),
      currency: currency != null && currency.isNotEmpty ? currency.toUpperCase() : 'USD',
      subtotal: subtotal,
      discountAmount: discountAmount,
      insuranceCoveredAmount: insuranceCoveredAmount,
      paidAmount: paidAmount,
      balance: balance,
      createdAt: createdAt,
      issuedAt: issuedAt,
      payments: _parsePayments(row['payments']),
    );
  }

  static List<Payment> _parsePayments(Object? raw) {
    if (raw is! List) {
      return const [];
    }

    final payments = <Payment>[];
    for (final entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final payment = Payment.fromRow(Map<String, dynamic>.from(entry));
      if (payment != null) {
        payments.add(payment);
      }
    }
    return payments;
  }

  static Money? _parseMoney(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is Money) {
      return raw;
    }
    if (raw is num) {
      return Money.tryParse(raw.toString());
    }
    return Money.tryParse(raw.toString());
  }

  InvoiceListItem copyWith({List<Payment>? payments}) {
    return InvoiceListItem(
      id: id,
      status: status,
      subtotal: subtotal,
      discountAmount: discountAmount,
      insuranceCoveredAmount: insuranceCoveredAmount,
      paidAmount: paidAmount,
      balance: balance,
      createdAt: createdAt,
      currency: currency,
      invoiceNumber: invoiceNumber,
      patientDisplayName: patientDisplayName,
      branchCode: branchCode,
      issuedAt: issuedAt,
      payments: payments ?? this.payments,
    );
  }
}
