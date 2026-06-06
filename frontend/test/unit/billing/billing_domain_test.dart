import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/payment.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InvoiceStatus', () {
    test('tryParse accepts wire values', () {
      expect(InvoiceStatus.tryParse('draft'), InvoiceStatus.draft);
      expect(InvoiceStatus.tryParse('partially_paid'), InvoiceStatus.partiallyPaid);
      expect(InvoiceStatus.tryParse('VOIDED'), InvoiceStatus.voided);
    });

    test('tryParse rejects unknown values', () {
      expect(InvoiceStatus.tryParse('cancelled'), isNull);
      expect(InvoiceStatus.tryParse(''), isNull);
      expect(InvoiceStatus.tryParse(null), isNull);
    });

    test('wireValue round-trips', () {
      for (final status in InvoiceStatus.values) {
        expect(InvoiceStatus.tryParse(status.wireValue), status);
      }
    });

    test('isDraft and isTerminal flags', () {
      expect(InvoiceStatus.draft.isDraft, isTrue);
      expect(InvoiceStatus.issued.isDraft, isFalse);
      expect(InvoiceStatus.paid.isTerminal, isTrue);
      expect(InvoiceStatus.voided.isTerminal, isTrue);
      expect(InvoiceStatus.partiallyPaid.isTerminal, isFalse);
    });
  });

  group('PaymentMethod', () {
    test('tryParse accepts wire values', () {
      expect(PaymentMethod.tryParse('bank_transfer'), PaymentMethod.bankTransfer);
      expect(PaymentMethod.tryParse('insurance_settlement'), PaymentMethod.insuranceSettlement);
    });

    test('isPatientTender excludes insurance settlement', () {
      expect(PaymentMethod.cash.isPatientTender, isTrue);
      expect(PaymentMethod.card.isPatientTender, isTrue);
      expect(PaymentMethod.bankTransfer.isPatientTender, isTrue);
      expect(PaymentMethod.insuranceSettlement.isPatientTender, isFalse);
    });
  });

  group('DiscountKind', () {
    test('tryParse accepts wire values', () {
      expect(DiscountKind.tryParse('percentage'), DiscountKind.percentage);
      expect(DiscountKind.tryParse('fixed'), DiscountKind.fixed);
      expect(DiscountKind.tryParse('percent'), isNull);
    });
  });

  group('Payment', () {
    test('fromRow parses recorded_by object with display_name', () {
      final payment = Payment.fromRow({
        'id': 'pay-1',
        'method': 'cash',
        'amount': '50.00',
        'reference': 'RCPT-1',
        'note': 'Full payment',
        'recorded_by': {'id': 'staff-uuid', 'display_name': 'Reception'},
        'recorded_at': '2026-06-01T12:00:00.000Z',
      });

      expect(payment, isNotNull);
      expect(payment!.recordedById, 'staff-uuid');
      expect(payment.recordedByDisplayName, 'Reception');
    });

    test('fromRow rejects recorded_by without id', () {
      expect(
        Payment.fromRow({
          'id': 'pay-1',
          'method': 'cash',
          'amount': '50.00',
          'recorded_by': {'display_name': 'Reception'},
          'recorded_at': '2026-06-01T12:00:00.000Z',
        }),
        isNull,
      );
    });
  });
}
