import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:flutter/foundation.dart';

/// Payment or refund row on an invoice (`get_invoice_detail`, V1-6).
@immutable
class Payment {
  const Payment({
    required this.id,
    required this.method,
    required this.amount,
    required this.recordedById,
    required this.recordedAt,
    this.reference,
    this.note,
    this.recordedByDisplayName,
  });

  final String id;
  final PaymentMethod method;
  final String amount;
  final String? reference;
  final String? note;
  final String recordedById;
  final String? recordedByDisplayName;
  final DateTime recordedAt;

  bool get isRefund {
    final parsed = double.tryParse(amount);
    return parsed != null && parsed < 0;
  }

  static Payment? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final method = PaymentMethod.tryParse(row['method']?.toString());
    final amount = row['amount']?.toString();
    final recordedBy = _parseRecordedBy(row['recorded_by']);
    final recordedAtRaw = row['recorded_at']?.toString();
    if (id == null || id.isEmpty || method == null || amount == null || recordedBy == null || recordedAtRaw == null) {
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
      recordedById: recordedBy.id,
      recordedByDisplayName: recordedBy.displayName,
      recordedAt: recordedAt,
    );
  }

  static ({String id, String? displayName})? _parseRecordedBy(Object? raw) {
    if (raw is Map) {
      final id = raw['id']?.toString();
      if (id == null || id.isEmpty) {
        return null;
      }
      return (id: id, displayName: raw['display_name']?.toString());
    }

    final id = raw?.toString();
    if (id == null || id.isEmpty) {
      return null;
    }
    return (id: id, displayName: null);
  }
}
