import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/billing/presentation/providers/visit_billing_flow_notifier.dart';
import 'package:ai_clinic/features/service_catalog/domain/effective_price.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

EligibleService _service({
  String serviceId = 'svc-1',
  String name = 'Consultation',
  String price = '100.00',
}) {
  return EligibleService(
    serviceId: serviceId,
    name: name,
    unitPrice: Money.parse(price),
    appliedRule: AppliedPriceRule.defaultPrice,
    onPromotion: false,
  );
}

void main() {
  group('VisitBillingFlowNotifier', () {
    late ProviderContainer container;
    late VisitBillingFlowNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
      notifier = container.read(visitBillingFlowProvider(_visitId).notifier);
    });

    VisitBillingFlowState readState() => container.read(visitBillingFlowProvider(_visitId));

    test('initial state uses documented defaults', () {
      expect(readState().step, VisitBillingStep.services);
      expect(readState().selectedLines, isEmpty);
      expect(readState().discountType, VisitBillingDiscountType.none);
      expect(readState().discountValue, 0);
      expect(readState().invoicePreviewNumber, isNull);
      expect(readState().isSubmitting, isFalse);
      expect(readState().invoicePreview, isNull);
    });

    test('beginBilling populates invoicePreviewNumber matching INV-YYYYMMDD-####', () {
      notifier.beginBilling();

      final number = readState().invoicePreviewNumber;
      expect(number, isNotNull);
      expect(number, matches(RegExp(r'^INV-\d{8}-\d{4}$')));
      expect(readState().invoicePreview, isNotNull);
      expect(readState().invoicePreview?.number, number);
    });

    test('setStep updates the workflow step', () {
      notifier.setStep(VisitBillingStep.invoice);

      expect(readState().step, VisitBillingStep.invoice);
    });

    test('toggleService(selected: true) appends a line and ignores duplicates', () {
      final service = _service();

      notifier.toggleService(service, selected: true);
      notifier.toggleService(service, selected: true);

      expect(readState().selectedLines, hasLength(1));
      expect(readState().selectedLines.single.serviceId, service.serviceId);
    });

    test('toggleService(selected: false) removes by serviceId and ignores missing lines', () {
      final service = _service();
      notifier.toggleService(service, selected: true);

      notifier.toggleService(_service(serviceId: 'missing'), selected: false);
      expect(readState().selectedLines, hasLength(1));

      notifier.toggleService(service, selected: false);
      expect(readState().selectedLines, isEmpty);
    });

    test('updateQuantity clamps to the supported bounds', () {
      notifier.toggleService(_service(), selected: true);

      notifier.updateQuantity('svc-1', 0);
      expect(readState().selectedLines.single.quantity, 1);

      notifier.updateQuantity('svc-1', 100);
      expect(readState().selectedLines.single.quantity, 99);

      notifier.updateQuantity('svc-1', 3);
      expect(readState().selectedLines.single.quantity, 3);
    });

    test('setDiscountType resets discountValue to zero', () {
      notifier.setDiscountValue(25);
      notifier.setDiscountType(VisitBillingDiscountType.percentage);

      expect(readState().discountType, VisitBillingDiscountType.percentage);
      expect(readState().discountValue, 0);
    });

    test('setDiscountValue updates the discount amount', () {
      notifier.setDiscountType(VisitBillingDiscountType.fixed);
      notifier.setDiscountValue(15);

      expect(readState().discountValue, 15);
    });

    test('setSubmitting toggles submission state', () {
      notifier.setSubmitting(true);
      expect(readState().isSubmitting, isTrue);

      notifier.setSubmitting(false);
      expect(readState().isSubmitting, isFalse);
    });

    test('reset returns to the initial state after progress', () {
      notifier.beginBilling();
      notifier.toggleService(_service(), selected: true);
      notifier.setStep(VisitBillingStep.invoice);
      notifier.setDiscountType(VisitBillingDiscountType.percentage);
      notifier.setDiscountValue(10);
      notifier.setSubmitting(true);

      notifier.reset();

      expect(readState().step, VisitBillingStep.services);
      expect(readState().selectedLines, isEmpty);
      expect(readState().discountType, VisitBillingDiscountType.none);
      expect(readState().discountValue, 0);
      expect(readState().invoicePreviewNumber, isNull);
      expect(readState().isSubmitting, isFalse);
    });

    test('totals matches computeVisitBillingTotals', () {
      notifier.toggleService(_service(price: '50.00'), selected: true);
      notifier.toggleService(_service(serviceId: 'svc-2', name: 'Labs', price: '25.00'), selected: true);
      notifier.updateQuantity('svc-2', 2);
      notifier.setDiscountType(VisitBillingDiscountType.percentage);
      notifier.setDiscountValue(10);

      final expected = computeVisitBillingTotals(
        readState().selectedLines,
        readState().discountType,
        readState().discountValue,
      );

      expect(readState().totals.subtotal, expected.subtotal);
      expect(readState().totals.discountAmount, expected.discountAmount);
      expect(readState().totals.total, expected.total);
    });

    test('copyWith clearInvoicePreviewNumber clears the preview number', () {
      notifier.beginBilling();
      final withNumber = readState().copyWith(isSubmitting: true);
      final cleared = withNumber.copyWith(clearInvoicePreviewNumber: true);

      expect(withNumber.invoicePreviewNumber, isNotNull);
      expect(withNumber.isSubmitting, isTrue);
      expect(cleared.invoicePreviewNumber, isNull);
      expect(cleared.isSubmitting, isTrue);
    });

    test('end-to-end billing preview sequence computes totals and preview', () {
      notifier.beginBilling();
      notifier.toggleService(_service(serviceId: 'svc-a', name: 'Consultation', price: '100.00'), selected: true);
      notifier.toggleService(_service(serviceId: 'svc-b', name: 'Labs', price: '40.00'), selected: true);
      notifier.updateQuantity('svc-b', 2);
      notifier.setDiscountType(VisitBillingDiscountType.percentage);
      notifier.setDiscountValue(10);

      final preview = readState().invoicePreview;
      expect(preview, isNotNull);
      expect(preview!.lines, hasLength(2));
      expect(preview.subtotal, 180);
      expect(preview.discountAmount, 18);
      expect(preview.total, 162);
      expect(preview.discountType, VisitBillingDiscountType.percentage);
      expect(preview.discountValue, 10);
      expect(preview.number, matches(RegExp(r'^INV-\d{8}-\d{4}$')));
    });
  });
}
