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

    VisitBillingFlowState get state => container.read(visitBillingFlowProvider(_visitId));

    test('initial state uses documented defaults', () {
      expect(state.step, VisitBillingStep.services);
      expect(state.selectedLines, isEmpty);
      expect(state.discountType, VisitBillingDiscountType.none);
      expect(state.discountValue, 0);
      expect(state.invoicePreviewNumber, isNull);
      expect(state.isSubmitting, isFalse);
      expect(state.invoicePreview, isNull);
    });

    test('beginBilling populates invoicePreviewNumber matching INV-YYYYMMDD-####', () {
      notifier.beginBilling();

      final number = state.invoicePreviewNumber;
      expect(number, isNotNull);
      expect(number, matches(RegExp(r'^INV-\d{8}-\d{4}$')));
      expect(state.invoicePreview, isNotNull);
      expect(state.invoicePreview?.number, number);
    });

    test('setStep updates the workflow step', () {
      notifier.setStep(VisitBillingStep.invoice);

      expect(state.step, VisitBillingStep.invoice);
    });

    test('toggleService(selected: true) appends a line and ignores duplicates', () {
      final service = _service();

      notifier.toggleService(service, selected: true);
      notifier.toggleService(service, selected: true);

      expect(state.selectedLines, hasLength(1));
      expect(state.selectedLines.single.serviceId, service.serviceId);
    });

    test('toggleService(selected: false) removes by serviceId and ignores missing lines', () {
      final service = _service();
      notifier.toggleService(service, selected: true);

      notifier.toggleService(_service(serviceId: 'missing'), selected: false);
      expect(state.selectedLines, hasLength(1));

      notifier.toggleService(service, selected: false);
      expect(state.selectedLines, isEmpty);
    });

    test('updateQuantity clamps to the supported bounds', () {
      notifier.toggleService(_service(), selected: true);

      notifier.updateQuantity('svc-1', 0);
      expect(state.selectedLines.single.quantity, 1);

      notifier.updateQuantity('svc-1', 100);
      expect(state.selectedLines.single.quantity, 99);

      notifier.updateQuantity('svc-1', 3);
      expect(state.selectedLines.single.quantity, 3);
    });

    test('setDiscountType resets discountValue to zero', () {
      notifier.setDiscountValue(25);
      notifier.setDiscountType(VisitBillingDiscountType.percentage);

      expect(state.discountType, VisitBillingDiscountType.percentage);
      expect(state.discountValue, 0);
    });

    test('setDiscountValue updates the discount amount', () {
      notifier.setDiscountType(VisitBillingDiscountType.fixed);
      notifier.setDiscountValue(15);

      expect(state.discountValue, 15);
    });

    test('setSubmitting toggles submission state', () {
      notifier.setSubmitting(true);
      expect(state.isSubmitting, isTrue);

      notifier.setSubmitting(false);
      expect(state.isSubmitting, isFalse);
    });

    test('reset returns to the initial state after progress', () {
      notifier.beginBilling();
      notifier.toggleService(_service(), selected: true);
      notifier.setStep(VisitBillingStep.invoice);
      notifier.setDiscountType(VisitBillingDiscountType.percentage);
      notifier.setDiscountValue(10);
      notifier.setSubmitting(true);

      notifier.reset();

      expect(state.step, VisitBillingStep.services);
      expect(state.selectedLines, isEmpty);
      expect(state.discountType, VisitBillingDiscountType.none);
      expect(state.discountValue, 0);
      expect(state.invoicePreviewNumber, isNull);
      expect(state.isSubmitting, isFalse);
    });

    test('totals matches computeVisitBillingTotals', () {
      notifier.toggleService(_service(price: '50.00'), selected: true);
      notifier.toggleService(_service(serviceId: 'svc-2', name: 'Labs', price: '25.00'), selected: true);
      notifier.updateQuantity('svc-2', 2);
      notifier.setDiscountType(VisitBillingDiscountType.percentage);
      notifier.setDiscountValue(10);

      final expected = computeVisitBillingTotals(
        state.selectedLines,
        state.discountType,
        state.discountValue,
      );

      expect(state.totals.subtotal, expected.subtotal);
      expect(state.totals.discountAmount, expected.discountAmount);
      expect(state.totals.total, expected.total);
    });

    test('copyWith clearInvoicePreviewNumber clears the preview number', () {
      notifier.beginBilling();
      final withNumber = state.copyWith(isSubmitting: true);
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

      final preview = state.invoicePreview;
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
