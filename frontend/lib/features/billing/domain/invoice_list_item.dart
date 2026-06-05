import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
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
  final String subtotal;
  final String discountAmount;
  final String insuranceCoveredAmount;
  final String paidAmount;
  final String balance;
  final DateTime createdAt;
  final DateTime? issuedAt;

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

    final issuedAtRaw = row['issued_at']?.toString();
    final issuedAt = issuedAtRaw == null ? null : DateTime.tryParse(issuedAtRaw);

    return InvoiceListItem(
      id: id,
      invoiceNumber: row['invoice_number']?.toString(),
      status: status,
      patientDisplayName: row['patient_display_name']?.toString(),
      branchCode: row['branch_code']?.toString(),
      subtotal: row['subtotal']?.toString() ?? '0',
      discountAmount: row['discount_amount']?.toString() ?? '0',
      insuranceCoveredAmount: row['insurance_covered_amount']?.toString() ?? '0',
      paidAmount: row['paid_amount']?.toString() ?? '0',
      balance: row['balance']?.toString() ?? '0',
      createdAt: createdAt,
      issuedAt: issuedAt,
    );
  }
}
