import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
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
    this.invoiceNumber,
    this.patientDisplayName,
    this.branchCode,
    this.issuedAt,
  });

  final String id;
  final String? invoiceNumber;
  final InvoiceStatus status;
  final String? patientDisplayName;
  final String? branchCode;
  final Money subtotal;
  final Money discountAmount;
  final Money insuranceCoveredAmount;
  final Money paidAmount;
  final Money balance;
  final DateTime createdAt;
  final DateTime? issuedAt;

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

    final subtotal = Money.tryParse(row['subtotal']?.toString());
    final discountAmount = Money.tryParse(row['discount_amount']?.toString());
    final insuranceCoveredAmount = Money.tryParse(row['insurance_covered_amount']?.toString());
    final paidAmount = Money.tryParse(row['paid_amount']?.toString());
    final balance = Money.tryParse(row['balance']?.toString());
    if (subtotal == null ||
        discountAmount == null ||
        insuranceCoveredAmount == null ||
        paidAmount == null ||
        balance == null) {
      return null;
    }

    final issuedAtRaw = row['issued_at']?.toString();
    final issuedAt = issuedAtRaw == null ? null : DateTime.tryParse(issuedAtRaw);

    return InvoiceListItem(
      id: id,
      invoiceNumber: row['invoice_number']?.toString(),
      status: status,
      patientDisplayName: row['patient_display_name']?.toString(),
      branchCode: row['branch_code']?.toString(),
      subtotal: subtotal,
      discountAmount: discountAmount,
      insuranceCoveredAmount: insuranceCoveredAmount,
      paidAmount: paidAmount,
      balance: balance,
      createdAt: createdAt,
      issuedAt: issuedAt,
    );
  }
}
