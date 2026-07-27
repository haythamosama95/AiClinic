import 'package:decimal/decimal.dart';

import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';

/// Maps persisted invoice data into visit-billing preview models.
abstract final class VisitBillingMapping {
  static List<VisitSelectedServiceLine> linesFromInvoice(
    List<InvoiceItem> items,
  ) {
    return items
        .map(
          (item) => VisitSelectedServiceLine(
            id: item.id,
            // Invoice items do not carry the originating catalog service id.
            serviceId: '',
            name: item.description,
            unitPrice: item.unitPrice,
            quantity: int.tryParse(item.quantity) ?? 1,
          ),
        )
        .toList(growable: false);
  }

  static ({VisitBillingDiscountType type, Decimal value}) discountFromInvoice(
    InvoiceDetail invoice,
  ) {
    if (invoice.discountAmount.isZero) {
      return (type: VisitBillingDiscountType.none, value: Decimal.zero);
    }

    final parsedValue = Decimal.tryParse(invoice.discountValue ?? '') ??
        Decimal.zero;
    return switch (invoice.discountKind) {
      DiscountKind.percentage => (
        type: VisitBillingDiscountType.percentage,
        value: parsedValue,
      ),
      DiscountKind.fixed => (
        type: VisitBillingDiscountType.fixed,
        value: parsedValue,
      ),
      null => (
        type: VisitBillingDiscountType.fixed,
        value: Decimal.parse(invoice.discountAmount.wireValue),
      ),
    };
  }
}
