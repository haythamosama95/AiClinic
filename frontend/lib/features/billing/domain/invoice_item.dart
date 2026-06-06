import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
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
  final Money unitPrice;
  final Money lineSubtotal;
  final DiscountKind? lineDiscountKind;
  final String? lineDiscountValue;
  final Money lineDiscountAmount;
  final Money lineTotal;

  static InvoiceItem? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final description = (row['description']?.toString() ?? '').trim();
    if (id == null || id.isEmpty || description.isEmpty) {
      return null;
    }

    final unitPrice = Money.tryParse(row['unit_price']?.toString());
    final lineSubtotal = Money.tryParse(row['line_subtotal']?.toString());
    final lineDiscountAmount = Money.tryParse(row['line_discount_amount']?.toString());
    final lineTotal = Money.tryParse(row['line_total']?.toString());
    if (unitPrice == null || lineSubtotal == null || lineDiscountAmount == null || lineTotal == null) {
      return null;
    }

    return InvoiceItem(
      id: id,
      description: description,
      quantity: row['quantity']?.toString() ?? '0',
      unitPrice: unitPrice,
      lineSubtotal: lineSubtotal,
      lineDiscountKind: DiscountKind.tryParse(row['line_discount_kind']?.toString()),
      lineDiscountValue: row['line_discount_value']?.toString(),
      lineDiscountAmount: lineDiscountAmount,
      lineTotal: lineTotal,
    );
  }
}
