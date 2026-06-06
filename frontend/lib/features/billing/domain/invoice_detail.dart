import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/domain/payment.dart';
import 'package:flutter/foundation.dart';

/// Full invoice envelope from `get_invoice_detail` (V1-6).
@immutable
class InvoiceDetail {
  const InvoiceDetail({
    required this.id,
    required this.status,
    required this.branchId,
    required this.patientId,
    required this.visitId,
    required this.subtotal,
    required this.discountAmount,
    required this.insuranceCoveredAmount,
    required this.currency,
    required this.balance,
    required this.updatedAt,
    required this.items,
    required this.payments,
    this.invoiceNumber,
    this.discountKind,
    this.discountValue,
    this.insuranceProviderId,
    this.issuedAt,
    this.voidedAt,
    this.voidReason,
    this.patientDisplayName,
    this.branchCode,
    this.branchName,
    this.insuranceProviderName,
  });

  final String id;
  final String? invoiceNumber;
  final InvoiceStatus status;
  final String branchId;
  final String patientId;
  final String visitId;
  final Money subtotal;
  final DiscountKind? discountKind;
  final String? discountValue;
  final Money discountAmount;
  final String? insuranceProviderId;
  final Money insuranceCoveredAmount;
  final String currency;
  final DateTime? issuedAt;
  final DateTime? voidedAt;
  final String? voidReason;
  final Money balance;
  final DateTime updatedAt;
  final List<InvoiceItem> items;
  final List<Payment> payments;
  final String? patientDisplayName;
  final String? branchCode;
  final String? branchName;
  final String? insuranceProviderName;

  static InvoiceDetail? fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }

    final invoiceRaw = data['invoice'];
    if (invoiceRaw is! Map) {
      return null;
    }

    final invoice = Map<String, dynamic>.from(invoiceRaw);
    final id = invoice['id']?.toString();
    final status = InvoiceStatus.tryParse(invoice['status']?.toString());
    final branchId = invoice['branch_id']?.toString();
    final patientId = invoice['patient_id']?.toString();
    final visitId = invoice['visit_id']?.toString();
    final updatedAtRaw = invoice['updated_at']?.toString();
    if (id == null ||
        id.isEmpty ||
        status == null ||
        branchId == null ||
        branchId.isEmpty ||
        patientId == null ||
        patientId.isEmpty ||
        visitId == null ||
        visitId.isEmpty ||
        updatedAtRaw == null) {
      return null;
    }

    final updatedAt = DateTime.tryParse(updatedAtRaw);
    if (updatedAt == null) {
      return null;
    }

    final subtotal = Money.tryParse(invoice['subtotal']?.toString());
    final discountAmount = Money.tryParse(invoice['discount_amount']?.toString());
    final insuranceCoveredAmount = Money.tryParse(invoice['insurance_covered_amount']?.toString());
    final balance = Money.tryParse(invoice['balance']?.toString());
    if (subtotal == null || discountAmount == null || insuranceCoveredAmount == null || balance == null) {
      return null;
    }

    final items = _parseItems(data['items']);
    final payments = _parsePayments(data['payments']);

    final patientRaw = data['patient'];
    final branchRaw = data['branch'];
    final providerRaw = data['insurance_provider'];

    return InvoiceDetail(
      id: id,
      invoiceNumber: invoice['invoice_number']?.toString(),
      status: status,
      branchId: branchId,
      patientId: patientId,
      visitId: visitId,
      subtotal: subtotal,
      discountKind: DiscountKind.tryParse(invoice['discount_kind']?.toString()),
      discountValue: invoice['discount_value']?.toString(),
      discountAmount: discountAmount,
      insuranceProviderId: invoice['insurance_provider_id']?.toString(),
      insuranceCoveredAmount: insuranceCoveredAmount,
      currency: invoice['currency']?.toString() ?? 'USD',
      issuedAt: _parseOptionalDate(invoice['issued_at']?.toString()),
      voidedAt: _parseOptionalDate(invoice['voided_at']?.toString()),
      voidReason: invoice['void_reason']?.toString(),
      balance: balance,
      updatedAt: updatedAt,
      items: items,
      payments: payments,
      patientDisplayName: patientRaw is Map ? patientRaw['display_name']?.toString() : null,
      branchCode: branchRaw is Map ? branchRaw['code']?.toString() : null,
      branchName: branchRaw is Map ? branchRaw['name']?.toString() : null,
      insuranceProviderName: providerRaw is Map ? providerRaw['name']?.toString() : null,
    );
  }

  static DateTime? _parseOptionalDate(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  static List<InvoiceItem> _parseItems(Object? raw) {
    if (raw is! List) {
      return const [];
    }

    return raw
        .whereType<Map>()
        .map((row) => InvoiceItem.fromRow(Map<String, dynamic>.from(row)))
        .whereType<InvoiceItem>()
        .toList(growable: false);
  }

  static List<Payment> _parsePayments(Object? raw) {
    if (raw is! List) {
      return const [];
    }

    return raw
        .whereType<Map>()
        .map((row) => Payment.fromRow(Map<String, dynamic>.from(row)))
        .whereType<Payment>()
        .toList(growable: false);
  }
}
