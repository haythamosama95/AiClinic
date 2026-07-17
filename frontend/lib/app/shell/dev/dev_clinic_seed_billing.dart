import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';

/// Billing outcome seeded for a completed visit invoice.
enum DevClinicBillingScenario {
  /// Completed visit with no invoice (empty billing tab case).
  none,

  /// Draft invoice with no line items.
  draftEmpty,

  /// Draft invoice with manual line items, not issued.
  draftWithItems,

  /// Issued invoice awaiting payment.
  issuedUnpaid,

  /// Issued invoice with a partial card payment.
  partiallyPaidCard,

  /// Issued invoice paid in full via cash.
  paidCash,

  /// Issued invoice paid in full via card.
  paidCard,

  /// Issued invoice paid in full via bank transfer.
  paidBankTransfer,

  /// Issued invoice voided before payment.
  voided,

  /// Issued invoice with a percentage line discount.
  withLineDiscount,

  /// Issued invoice with a fixed invoice-level discount.
  withInvoiceDiscount,

  /// Issued invoice with insurance coverage and patient cash payment.
  withInsuranceAndPatientPayment,

  /// Issued invoice with insurance settlement partial payment.
  withInsuranceSettlementPartial,

  /// Draft invoice with a service-catalog line item.
  withServiceCatalogItem,

  /// Issued invoice paid via two patient-tender payments (card + cash).
  splitPaymentCashAndCard,

  /// Issued invoice paid in full, then partially refunded.
  paidWithPartialRefund,

  /// Issued invoice paid in full, then fully refunded back to unpaid.
  paidWithFullRefund,
}

/// A payment or refund step applied during dev billing seeding.
typedef DevClinicPaymentSeed = ({PaymentMethod method, String amount, String? reference, String? note, bool isRefund});

/// Deterministic billing scenarios for dev clinic seeding.
abstract final class DevClinicSeedBilling {
  static const scenarios = <DevClinicBillingScenario>[
    DevClinicBillingScenario.draftEmpty,
    DevClinicBillingScenario.draftWithItems,
    DevClinicBillingScenario.issuedUnpaid,
    DevClinicBillingScenario.partiallyPaidCard,
    DevClinicBillingScenario.paidCash,
    DevClinicBillingScenario.paidCard,
    DevClinicBillingScenario.paidBankTransfer,
    DevClinicBillingScenario.voided,
    DevClinicBillingScenario.withLineDiscount,
    DevClinicBillingScenario.withInvoiceDiscount,
    DevClinicBillingScenario.withInsuranceAndPatientPayment,
    DevClinicBillingScenario.withInsuranceSettlementPartial,
    DevClinicBillingScenario.withServiceCatalogItem,
    DevClinicBillingScenario.splitPaymentCashAndCard,
    DevClinicBillingScenario.paidWithPartialRefund,
    DevClinicBillingScenario.paidWithFullRefund,
  ];

  /// Terminal invoice statuses represented across [scenarios].
  static const coveredInvoiceStatuses = {'draft', 'issued', 'partially_paid', 'paid', 'voided'};

  static DevClinicBillingScenario scenarioFor(int seedKey) {
    return scenarios[seedKey % scenarios.length];
  }

  static bool shouldSeedInvoice(DevClinicBillingScenario scenario) => true;

  static bool shouldIssue(DevClinicBillingScenario scenario) {
    return switch (scenario) {
      DevClinicBillingScenario.draftEmpty ||
      DevClinicBillingScenario.draftWithItems ||
      DevClinicBillingScenario.withServiceCatalogItem => false,
      _ => true,
    };
  }

  static bool shouldAddManualItems(DevClinicBillingScenario scenario) {
    return switch (scenario) {
      DevClinicBillingScenario.draftEmpty || DevClinicBillingScenario.withServiceCatalogItem => false,
      _ => true,
    };
  }

  static bool shouldUseServiceCatalog(DevClinicBillingScenario scenario) {
    return scenario == DevClinicBillingScenario.withServiceCatalogItem;
  }

  static bool shouldApplyLineDiscount(DevClinicBillingScenario scenario) {
    return scenario == DevClinicBillingScenario.withLineDiscount;
  }

  static bool shouldApplyInvoiceDiscount(DevClinicBillingScenario scenario) {
    return scenario == DevClinicBillingScenario.withInvoiceDiscount;
  }

  static bool shouldApplyInsurance(DevClinicBillingScenario scenario) {
    return scenario == DevClinicBillingScenario.withInsuranceAndPatientPayment ||
        scenario == DevClinicBillingScenario.withInsuranceSettlementPartial;
  }

  static bool shouldVoid(DevClinicBillingScenario scenario) => scenario == DevClinicBillingScenario.voided;

  static List<DevClinicPaymentSeed> paymentsFor(DevClinicBillingScenario scenario) {
    return switch (scenario) {
      DevClinicBillingScenario.partiallyPaidCard => [
        (
          method: PaymentMethod.card,
          amount: '40.00',
          reference: 'SEED-CARD-1',
          note: 'Dev seed partial payment',
          isRefund: false,
        ),
      ],
      DevClinicBillingScenario.paidCash => [
        (
          method: PaymentMethod.cash,
          amount: '125.00',
          reference: null,
          note: 'Dev seed full cash payment',
          isRefund: false,
        ),
      ],
      DevClinicBillingScenario.paidCard => [
        (
          method: PaymentMethod.card,
          amount: '125.00',
          reference: 'SEED-CARD-FULL',
          note: 'Dev seed full card payment',
          isRefund: false,
        ),
      ],
      DevClinicBillingScenario.paidBankTransfer => [
        (
          method: PaymentMethod.bankTransfer,
          amount: '125.00',
          reference: 'SEED-BANK-1',
          note: 'Dev seed bank transfer payment',
          isRefund: false,
        ),
      ],
      DevClinicBillingScenario.withInsuranceAndPatientPayment => [
        (
          method: PaymentMethod.cash,
          amount: '30.00',
          reference: null,
          note: 'Dev seed patient co-pay after insurance',
          isRefund: false,
        ),
      ],
      DevClinicBillingScenario.withInsuranceSettlementPartial => [
        (
          method: PaymentMethod.insuranceSettlement,
          amount: '35.00',
          reference: 'SEED-CLM-1',
          note: 'Dev seed insurance settlement',
          isRefund: false,
        ),
      ],
      DevClinicBillingScenario.splitPaymentCashAndCard => [
        (
          method: PaymentMethod.card,
          amount: '75.00',
          reference: 'SEED-SPLIT-CARD',
          note: 'Dev seed split payment (card portion)',
          isRefund: false,
        ),
        (
          method: PaymentMethod.cash,
          amount: '50.00',
          reference: null,
          note: 'Dev seed split payment (cash portion)',
          isRefund: false,
        ),
      ],
      DevClinicBillingScenario.paidWithPartialRefund => [
        (
          method: PaymentMethod.cash,
          amount: '125.00',
          reference: null,
          note: 'Dev seed full payment before partial refund',
          isRefund: false,
        ),
        (
          method: PaymentMethod.cash,
          amount: '50.00',
          reference: null,
          note: 'Dev seed partial refund after over-collection',
          isRefund: true,
        ),
      ],
      DevClinicBillingScenario.paidWithFullRefund => [
        (
          method: PaymentMethod.card,
          amount: '125.00',
          reference: 'SEED-REFUND-FULL',
          note: 'Dev seed full payment before full refund',
          isRefund: false,
        ),
        (
          method: PaymentMethod.card,
          amount: '125.00',
          reference: null,
          note: 'Dev seed full refund restoring unpaid balance',
          isRefund: true,
        ),
      ],
      _ => const [],
    };
  }

  /// Expected terminal invoice status after all payment/refund steps complete.
  static String? terminalInvoiceStatusAfterPayments(DevClinicBillingScenario scenario) {
    return switch (scenario) {
      DevClinicBillingScenario.issuedUnpaid => 'issued',
      DevClinicBillingScenario.partiallyPaidCard ||
      DevClinicBillingScenario.withInsuranceAndPatientPayment ||
      DevClinicBillingScenario.withInsuranceSettlementPartial ||
      DevClinicBillingScenario.paidWithPartialRefund => 'partially_paid',
      DevClinicBillingScenario.paidCash ||
      DevClinicBillingScenario.paidCard ||
      DevClinicBillingScenario.paidBankTransfer ||
      DevClinicBillingScenario.splitPaymentCashAndCard => 'paid',
      DevClinicBillingScenario.paidWithFullRefund => 'issued',
      _ => null,
    };
  }

  static DiscountKind? lineDiscountKind(DevClinicBillingScenario scenario) {
    return shouldApplyLineDiscount(scenario) ? DiscountKind.percentage : null;
  }

  static String? lineDiscountValue(DevClinicBillingScenario scenario) {
    return shouldApplyLineDiscount(scenario) ? '10' : null;
  }

  static DiscountKind? invoiceDiscountKind(DevClinicBillingScenario scenario) {
    return shouldApplyInvoiceDiscount(scenario) ? DiscountKind.fixed : null;
  }

  static String? invoiceDiscountValue(DevClinicBillingScenario scenario) {
    return shouldApplyInvoiceDiscount(scenario) ? '15.00' : null;
  }

  static String insuranceCoveredAmount(DevClinicBillingScenario scenario) {
    return switch (scenario) {
      DevClinicBillingScenario.withInsuranceAndPatientPayment => '70.00',
      DevClinicBillingScenario.withInsuranceSettlementPartial => '40.00',
      _ => '0',
    };
  }

  static String primaryItemDescription({required String branchCode, required int patientIndex}) {
    return 'Dev seed consultation — $branchCode patient #$patientIndex';
  }

  static String secondaryItemDescription() => 'Dev seed lab panel';

  static String primaryItemUnitPrice() => '100.00';

  static String secondaryItemQuantity() => '1';

  static String secondaryItemUnitPrice() => '25.00';

  static String voidReason({required String branchCode, required int patientIndex}) {
    return 'Dev seed void for $branchCode patient #$patientIndex.';
  }
}
