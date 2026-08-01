import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/service_catalog/domain/effective_price.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';
import 'package:flutter_test/flutter_test.dart';

VisitSelectedServiceLine _line({
  String id = 'line-1',
  String serviceId = 'svc-1',
  String name = 'Consultation',
  double unitPrice = 100.0,
  int quantity = 1,
}) {
  return VisitSelectedServiceLine(
    id: id,
    serviceId: serviceId,
    name: name,
    unitPrice: unitPrice,
    quantity: quantity,
  );
}

void main() {
  group('computeVisitBillingTotals', () {
    test('empty lines yields all zero totals', () {
      final totals = computeVisitBillingTotals(
        const [],
        VisitBillingDiscountType.percentage,
        10,
      );

      expect(totals.subtotal, 0);
      expect(totals.discountAmount, 0);
      expect(totals.total, 0);
    });

    test('single line subtotal is unitPrice times quantity', () {
      final totals = computeVisitBillingTotals(
        [_line(unitPrice: 50, quantity: 2)],
        VisitBillingDiscountType.none,
        0,
      );

      expect(totals.subtotal, 100);
      expect(totals.discountAmount, 0);
      expect(totals.total, 100);
    });

    test('multiple lines sum unitPrice times quantity', () {
      final totals = computeVisitBillingTotals(
        [
          _line(unitPrice: 50, quantity: 2),
          _line(id: 'line-2', unitPrice: 25, quantity: 3),
        ],
        VisitBillingDiscountType.none,
        0,
      );

      expect(totals.subtotal, 175);
      expect(totals.total, 175);
    });

    test('percentage discount applies normally', () {
      final totals = computeVisitBillingTotals(
        [_line(unitPrice: 100, quantity: 1)],
        VisitBillingDiscountType.percentage,
        10,
      );

      expect(totals.subtotal, 100);
      expect(totals.discountAmount, 10);
      expect(totals.total, 90);
    });

    test('percentage discount of zero yields no discount', () {
      final totals = computeVisitBillingTotals(
        [_line(unitPrice: 100, quantity: 1)],
        VisitBillingDiscountType.percentage,
        0,
      );

      expect(totals.discountAmount, 0);
      expect(totals.total, 100);
    });

    test('negative percentage discount yields no discount', () {
      final totals = computeVisitBillingTotals(
        [_line(unitPrice: 100, quantity: 1)],
        VisitBillingDiscountType.percentage,
        -5,
      );

      expect(totals.discountAmount, 0);
      expect(totals.total, 100);
    });

    test('percentage discount of exactly 100 removes full subtotal', () {
      final totals = computeVisitBillingTotals(
        [_line(unitPrice: 100, quantity: 1)],
        VisitBillingDiscountType.percentage,
        100,
      );

      expect(totals.discountAmount, 100);
      expect(totals.total, 0);
    });

    test('percentage discount over 100 is clamped to subtotal', () {
      final totals = computeVisitBillingTotals(
        [_line(unitPrice: 100, quantity: 1)],
        VisitBillingDiscountType.percentage,
        150,
      );

      expect(totals.discountAmount, 100);
      expect(totals.total, 0);
    });

    test('fixed discount applies normally', () {
      final totals = computeVisitBillingTotals(
        [_line(unitPrice: 100, quantity: 1)],
        VisitBillingDiscountType.fixed,
        25,
      );

      expect(totals.subtotal, 100);
      expect(totals.discountAmount, 25);
      expect(totals.total, 75);
    });

    test('fixed discount exceeding subtotal is clamped', () {
      final totals = computeVisitBillingTotals(
        [_line(unitPrice: 100, quantity: 1)],
        VisitBillingDiscountType.fixed,
        200,
      );

      expect(totals.discountAmount, 100);
      expect(totals.total, 0);
    });

    test('fixed discount of zero yields no discount', () {
      final totals = computeVisitBillingTotals(
        [_line(unitPrice: 100, quantity: 1)],
        VisitBillingDiscountType.fixed,
        0,
      );

      expect(totals.discountAmount, 0);
      expect(totals.total, 100);
    });

    test('negative fixed discount yields no discount', () {
      final totals = computeVisitBillingTotals(
        [_line(unitPrice: 100, quantity: 1)],
        VisitBillingDiscountType.fixed,
        -10,
      );

      expect(totals.discountAmount, 0);
      expect(totals.total, 100);
    });

    test('none discount type ignores non-zero value', () {
      final totals = computeVisitBillingTotals(
        [_line(unitPrice: 100, quantity: 1)],
        VisitBillingDiscountType.none,
        50,
      );

      expect(totals.discountAmount, 0);
      expect(totals.total, 100);
    });

    test('total equals subtotal minus discountAmount for percentage', () {
      final totals = computeVisitBillingTotals(
        [_line(unitPrice: 80, quantity: 2)],
        VisitBillingDiscountType.percentage,
        15,
      );

      expect(totals.total, totals.subtotal - totals.discountAmount);
    });

    test('total equals subtotal minus discountAmount for fixed', () {
      final totals = computeVisitBillingTotals(
        [_line(unitPrice: 80, quantity: 2)],
        VisitBillingDiscountType.fixed,
        30,
      );

      expect(totals.total, totals.subtotal - totals.discountAmount);
    });
  });

  group('VisitSelectedServiceLine', () {
    test('lineTotal is unitPrice times quantity', () {
      final line = _line(unitPrice: 12.5, quantity: 4);
      expect(line.lineTotal, 50);
    });

    test('copyWith updates quantity', () {
      final line = _line(quantity: 1);
      final updated = line.copyWith(quantity: 3);

      expect(updated.quantity, 3);
      expect(updated.id, line.id);
      expect(updated.serviceId, line.serviceId);
      expect(updated.unitPrice, line.unitPrice);
    });

    test('fromEligibleService maps fields and prefixes id with line-serviceId', () {
      final service = EligibleService(
        serviceId: 'svc-42',
        name: 'X-Ray',
        unitPrice: Money.parse('75.00'),
        appliedRule: AppliedPriceRule.defaultPrice,
        onPromotion: false,
      );

      final line = VisitSelectedServiceLine.fromEligibleService(service);

      expect(line.serviceId, 'svc-42');
      expect(line.name, 'X-Ray');
      expect(line.unitPrice, 75.0);
      expect(line.quantity, 1);
      expect(line.id.startsWith('line-svc-42-'), isTrue);
    });
  });

  group('generateVisitBillingInvoicePreviewNumber', () {
    test('matches INV-YYYYMMDD-#### shape', () {
      final number = generateVisitBillingInvoicePreviewNumber();
      expect(
        number,
        matches(RegExp(r'^INV-\d{8}-\d{4}$')),
      );
    });
  });
}
