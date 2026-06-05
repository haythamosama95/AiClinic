import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:flutter/foundation.dart';

/// Line item on a draft or issued invoice (`get_invoice_detail`, V1-6).
@immutable
class InvoiceItem {
  const InvoiceItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.lineSubtotal,
    required this.lineDiscountAmount,
    required this.lineTotal,
    this.lineDiscountKind,
    this.lineDiscountValue,
  });

  final String id;
  final String description;
  final String quantity;
  final String unitPrice;
  final String lineSubtotal;
  final DiscountKind? lineDiscountKind;
  final String? lineDiscountValue;
  final String lineDiscountAmount;
  final String lineTotal;

  static InvoiceItem? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final description = row['description']?.toString().trim();
    if (id == null || id.isEmpty || description == null || description.isEmpty) {
      return null;
    }

    return InvoiceItem(
      id: id,
      description: description,
      quantity: row['quantity']?.toString() ?? '0',
      unitPrice: row['unit_price']?.toString() ?? '0',
      lineSubtotal: row['line_subtotal']?.toString() ?? '0',
      lineDiscountKind: DiscountKind.tryParse(row['line_discount_kind']?.toString()),
      lineDiscountValue: row['line_discount_value']?.toString(),
      lineDiscountAmount: row['line_discount_amount']?.toString() ?? '0',
      lineTotal: row['line_total']?.toString() ?? '0',
    );
  }
}
