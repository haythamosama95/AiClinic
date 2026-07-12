import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_billing.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DevClinicSeedBilling', () {
    test('cycles through every billing scenario including no-invoice visits', () {
      final seen = <DevClinicBillingScenario>{};
      for (var seedKey = 0; seedKey < DevClinicSeedBilling.scenarios.length * 3; seedKey++) {
        seen.add(DevClinicSeedBilling.scenarioFor(seedKey));
      }
      expect(seen, DevClinicSeedBilling.scenarios.toSet());
    });

    test('covers all invoice terminal and draft statuses', () {
      final statuses = <String>{};
      for (final scenario in DevClinicSeedBilling.scenarios) {
        if (!DevClinicSeedBilling.shouldSeedInvoice(scenario)) {
          continue;
        }
        if (!DevClinicSeedBilling.shouldIssue(scenario)) {
          statuses.add('draft');
          continue;
        }
        if (DevClinicSeedBilling.shouldVoid(scenario)) {
          statuses.add('voided');
          continue;
        }

        final terminalStatus = DevClinicSeedBilling.terminalInvoiceStatusAfterPayments(scenario);
        if (terminalStatus != null) {
          statuses.add(terminalStatus);
        }
      }

      expect(statuses, DevClinicSeedBilling.coveredInvoiceStatuses);
    });

    test('includes service catalog, discounts, insurance, payment methods, refunds, and split payments', () {
      expect(DevClinicSeedBilling.scenarios, contains(DevClinicBillingScenario.withServiceCatalogItem));
      expect(DevClinicSeedBilling.scenarios, contains(DevClinicBillingScenario.withLineDiscount));
      expect(DevClinicSeedBilling.scenarios, contains(DevClinicBillingScenario.withInvoiceDiscount));
      expect(DevClinicSeedBilling.scenarios, contains(DevClinicBillingScenario.withInsuranceAndPatientPayment));
      expect(DevClinicSeedBilling.scenarios, contains(DevClinicBillingScenario.withInsuranceSettlementPartial));
      expect(DevClinicSeedBilling.scenarios, contains(DevClinicBillingScenario.splitPaymentCashAndCard));
      expect(DevClinicSeedBilling.scenarios, contains(DevClinicBillingScenario.paidWithPartialRefund));
      expect(DevClinicSeedBilling.scenarios, contains(DevClinicBillingScenario.paidWithFullRefund));

      final methods = DevClinicSeedBilling.scenarios
          .expand((scenario) => DevClinicSeedBilling.paymentsFor(scenario).map((payment) => payment.method))
          .toSet();
      expect(methods, containsAll([PaymentMethod.cash, PaymentMethod.card, PaymentMethod.bankTransfer]));
      expect(methods, contains(PaymentMethod.insuranceSettlement));

      final paymentSteps = DevClinicSeedBilling.scenarios.expand(DevClinicSeedBilling.paymentsFor).toList();
      expect(paymentSteps.any((step) => step.isRefund), isTrue);
      expect(paymentSteps.any((step) => !step.isRefund), isTrue);
      expect(
        DevClinicSeedBilling.paymentsFor(
          DevClinicBillingScenario.splitPaymentCashAndCard,
        ).where((step) => !step.isRefund),
        hasLength(2),
      );
    });
  });
}
