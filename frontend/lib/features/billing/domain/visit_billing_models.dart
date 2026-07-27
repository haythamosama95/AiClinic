import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import 'package:ai_clinic/core/money/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';

/// Billing sub-step within the post-review visit workflow (web `BillingStep`).
enum VisitBillingStep { services, invoice }

/// Discount selection for the invoice review preview (web `DiscountType`).
enum VisitBillingDiscountType { none, percentage, fixed }

/// A selected catalog service line before invoice persistence (web `SelectedServiceLine`).
@immutable
class VisitSelectedServiceLine {
  const VisitSelectedServiceLine({
    required this.id,
    required this.serviceId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
  });

  final String id;
  final String serviceId;
  final String name;
  final Money unitPrice;
  final int quantity;

  Money get lineTotal => unitPrice * quantity;

  VisitSelectedServiceLine copyWith({int? quantity}) {
    return VisitSelectedServiceLine(
      id: id,
      serviceId: serviceId,
      name: name,
      unitPrice: unitPrice,
      quantity: quantity ?? this.quantity,
    );
  }

  static VisitSelectedServiceLine fromEligibleService(EligibleService service) {
    return VisitSelectedServiceLine(
      id: 'line-${service.serviceId}-${DateTime.now().microsecondsSinceEpoch}',
      serviceId: service.serviceId,
      name: service.name,
      unitPrice: service.unitPrice,
      quantity: 1,
    );
  }
}

/// Computed invoice totals for the billing preview step.
@immutable
class VisitBillingTotals {
  const VisitBillingTotals({
    required this.subtotal,
    required this.discountAmount,
    required this.total,
  });

  final Money subtotal;
  final Money discountAmount;
  final Money total;
}

Money visitBillingLineTotal(VisitSelectedServiceLine line) => line.lineTotal;

VisitBillingTotals computeVisitBillingTotals(
  List<VisitSelectedServiceLine> lines,
  VisitBillingDiscountType discountType,
  Decimal discountValue,
) {
  final subtotal = lines.fold<Money>(
    Money.zero,
    (sum, line) => sum + visitBillingLineTotal(line),
  );
  var discountAmount = Money.zero;

  if (discountType == VisitBillingDiscountType.percentage &&
      discountValue > Decimal.zero) {
    discountAmount = subtotal.percentageOf(discountValue).clampToZeroAnd(subtotal);
  } else if (discountType == VisitBillingDiscountType.fixed &&
      discountValue > Decimal.zero) {
    discountAmount = Money.parse(discountValue.toString()).clampToZeroAnd(subtotal);
  }

  return VisitBillingTotals(
    subtotal: subtotal,
    discountAmount: discountAmount,
    total: subtotal - discountAmount,
  );
}

/// Client-side draft invoice preview shown before persistence (web `VisitInvoice`).
@immutable
class VisitBillingInvoicePreview {
  const VisitBillingInvoicePreview({
    required this.number,
    required this.lines,
    required this.discountType,
    required this.discountValue,
    required this.subtotal,
    required this.discountAmount,
    required this.total,
  });

  final String number;
  final List<VisitSelectedServiceLine> lines;
  final VisitBillingDiscountType discountType;
  final Decimal discountValue;
  final Money subtotal;
  final Money discountAmount;
  final Money total;
}

String generateVisitBillingInvoicePreviewNumber() {
  final now = DateTime.now();
  final stamp =
      '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  final suffix = (now.millisecondsSinceEpoch % 10000).toString().padLeft(
    4,
    '0',
  );
  return 'INV-$stamp-$suffix';
}
