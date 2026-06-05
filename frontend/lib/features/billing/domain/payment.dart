import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:flutter/foundation.dart';

/// Payment or refund row on an invoice (`get_invoice_detail`, V1-6).
@immutable
class Payment {
  const Payment({
    required this.id,
    required this.method,
    required this.amount,
    required this.recordedBy,
    required this.recordedAt,
    this.reference,
    this.note,
  });

  final String id;
  final PaymentMethod method;
  final String amount;
  final String? reference;
  final String? note;
  final String recordedBy;
  final DateTime recordedAt;

  bool get isRefund {
    final parsed = double.tryParse(amount);
    return parsed != null && parsed < 0;
  }

  static Payment? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final method = PaymentMethod.tryParse(row['method']?.toString());
    final amount = row['amount']?.toString();
    final recordedBy = row['recorded_by']?.toString();
    final recordedAtRaw = row['recorded_at']?.toString();
    if (id == null ||
        id.isEmpty ||
        method == null ||
        amount == null ||
        recordedBy == null ||
        recordedBy.isEmpty ||
        recordedAtRaw == null) {
      return null;
    }

    final recordedAt = DateTime.tryParse(recordedAtRaw);
    if (recordedAt == null) {
      return null;
    }

    return Payment(
      id: id,
      method: method,
      amount: amount,
      reference: row['reference']?.toString(),
      note: row['note']?.toString(),
      recordedBy: recordedBy,
      recordedAt: recordedAt,
    );
  }
}
