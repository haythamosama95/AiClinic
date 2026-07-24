import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/domain/payment.dart';
import 'package:flutter/foundation.dart';

/// Completed visit summary embedded in `get_invoice_detail` when available.
@immutable
class VisitSummary {
  const VisitSummary({
    required this.date,
    required this.doctor,
    required this.branch,
  });

  final DateTime date;
  final String doctor;
  final String branch;

  static VisitSummary? fromRpcData(Object? raw) {
    if (raw is! Map) {
      return null;
    }

    final map = Map<String, dynamic>.from(raw);
    final date = _parseVisitDate(
      map['visit_date'] ?? map['date'] ?? map['started_at'],
    );
    final doctor = _parseOptionalString(map['doctor_name'] ?? map['doctor']);
    final branch = _parseOptionalString(map['branch_name'] ?? map['branch']);
    if (date == null || doctor == null || branch == null) {
      return null;
    }

    return VisitSummary(date: date, doctor: doctor, branch: branch);
  }

  static DateTime? _parseVisitDate(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is DateTime) {
      return DateTime.utc(raw.year, raw.month, raw.day);
    }
    final text = raw.toString().trim();
    if (text.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return null;
    }
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  static String? _parseOptionalString(Object? raw) {
    final text = raw?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

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
    required this.createdAt,
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
    this.voidedByName,
    this.patientDisplayName,
    this.patientMrn,
    this.patientPhone,
    this.branchCode,
    this.branchName,
    this.insuranceProviderName,
    this.visitSummary,
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
  final String? voidedByName;
  final Money balance;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<InvoiceItem> items;
  final List<Payment> payments;
  final String? patientDisplayName;
  final String? patientMrn;
  final String? patientPhone;
  final String? branchCode;
  final String? branchName;
  final String? insuranceProviderName;
  final VisitSummary? visitSummary;

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
    final createdAt = _parseOptionalDate(invoice['created_at']?.toString()) ?? updatedAt;

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
      voidedByName: _parseVoidedByName(invoice, data),
      balance: balance,
      createdAt: createdAt,
      updatedAt: updatedAt,
      items: items,
      payments: payments,
      patientDisplayName: patientRaw is Map ? patientRaw['display_name']?.toString() : null,
      patientMrn: patientRaw is Map ? _parseOptionalString(patientRaw['mrn'] ?? patientRaw['patient_mrn']) : null,
      patientPhone: patientRaw is Map ? _parseOptionalString(patientRaw['phone']) : null,
      branchCode: branchRaw is Map ? branchRaw['code']?.toString() : null,
      branchName: branchRaw is Map ? branchRaw['name']?.toString() : null,
      insuranceProviderName: providerRaw is Map ? providerRaw['name']?.toString() : null,
      visitSummary: VisitSummary.fromRpcData(data['visit']),
    );
  }

  static String? _parseVoidedByName(Map<String, dynamic> invoice, Map<String, dynamic> data) {
    final directName = _parseOptionalString(invoice['voided_by_name']);
    if (directName != null) {
      return directName;
    }

    final voidedByRaw = invoice['voided_by'] ?? data['voided_by'];
    if (voidedByRaw is Map) {
      return _parseOptionalString(voidedByRaw['display_name'] ?? voidedByRaw['full_name']);
    }

    return null;
  }

  static String? _parseOptionalString(Object? raw) {
    final text = raw?.toString().trim();
    return text == null || text.isEmpty ? null : text;
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
