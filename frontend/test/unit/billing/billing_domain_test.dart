import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
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

  group('InvoiceDetail', () {
    Map<String, dynamic> minimalEnvelope({
      Map<String, dynamic>? invoiceOverrides,
      Map<String, dynamic>? envelopeOverrides,
    }) {
      return {
        'invoice': {
          'id': 'inv-1',
          'status': 'issued',
          'branch_id': 'branch-1',
          'patient_id': 'patient-1',
          'visit_id': 'visit-1',
          'subtotal': '100.00',
          'discount_amount': '0.00',
          'insurance_covered_amount': '0.00',
          'balance': '100.00',
          'updated_at': '2026-06-02T12:00:00.000Z',
          ...?invoiceOverrides,
        },
        'items': const [],
        'payments': const [],
        'patient': {'id': 'patient-1', 'display_name': 'Test Patient'},
        'branch': {'id': 'branch-1', 'code': 'MAIN', 'name': 'Main'},
        ...?envelopeOverrides,
      };
    }

    test('fromRpcData parses enrichment fields when present', () {
      final detail = InvoiceDetail.fromRpcData(
        minimalEnvelope(
          invoiceOverrides: {
            'created_at': '2026-06-01T10:00:00.000Z',
            'voided_at': '2026-06-02T11:00:00.000Z',
            'void_reason': 'Duplicate',
            'voided_by': {'id': 'staff-1', 'display_name': 'Front Desk'},
          },
          envelopeOverrides: {
            'patient': {
              'id': 'patient-1',
              'display_name': 'Test Patient',
              'mrn': 'MRN-10482',
              'phone': '+20 100 000 0000',
            },
            'visit': {'visit_date': '2026-06-01', 'doctor_name': 'Dr. Smith', 'branch_name': 'Main'},
          },
        ),
      );

      expect(detail, isNotNull);
      expect(detail!.createdAt, DateTime.parse('2026-06-01T10:00:00.000Z'));
      expect(detail.voidedByName, 'Front Desk');
      expect(detail.patientMrn, 'MRN-10482');
      expect(detail.patientPhone, '+20 100 000 0000');
      expect(detail.visitSummary?.doctor, 'Dr. Smith');
      expect(detail.visitSummary?.branch, 'Main');
      expect(detail.visitSummary?.date, DateTime.utc(2026, 6, 1));
    });

    test('fromRpcData degrades when enrichment fields are absent', () {
      final detail = InvoiceDetail.fromRpcData(minimalEnvelope());

      expect(detail, isNotNull);
      expect(detail!.createdAt, DateTime.parse('2026-06-02T12:00:00.000Z'));
      expect(detail.voidedByName, isNull);
      expect(detail.patientMrn, isNull);
      expect(detail.patientPhone, isNull);
      expect(detail.visitSummary, isNull);
    });

    test('VisitSummary.fromRpcData rejects partial visit payloads', () {
      expect(VisitSummary.fromRpcData({'visit_date': '2026-06-01', 'doctor_name': 'Dr. Smith'}), isNull);
    });
  });

  group('InvoiceListItem', () {
    test('fromRow parses nested payments', () {
      final item = InvoiceListItem.fromRow({
        'id': 'inv-1',
        'status': 'partially_paid',
        'subtotal': '100.00',
        'discount_amount': '0.00',
        'insurance_covered_amount': '0.00',
        'paid_amount': '40.00',
        'balance': '60.00',
        'currency': 'EGP',
        'created_at': '2026-06-01T10:00:00.000Z',
        'payments': [
          {
            'id': 'pay-1',
            'method': 'cash',
            'amount': '40.00',
            'recorded_by': {'id': 'staff-uuid', 'display_name': 'Reception'},
            'recorded_at': '2026-06-01T12:00:00.000Z',
          },
        ],
      });

      expect(item, isNotNull);
      expect(item!.payments, hasLength(1));
      expect(item.currency, 'EGP');
      expect(item.payments.first.method, PaymentMethod.cash);
      expect(item.payments.first.amount.wireValue, '40.00');
    });

    test('fromRow parses numeric wire amounts from list_patient_invoices', () {
      final item = InvoiceListItem.fromRow({
        'id': 'inv-1',
        'status': 'partially_paid',
        'subtotal': 125.0,
        'discount_amount': 0.0,
        'insurance_covered_amount': 0.0,
        'paid_amount': 75.0,
        'balance': 50.0,
        'created_at': '2026-06-01T10:00:00.000Z',
        'payments': [
          {
            'id': 'pay-1',
            'method': 'cash',
            'amount': 125.0,
            'recorded_by': {'id': 'staff-uuid', 'display_name': 'Reception'},
            'recorded_at': '2026-06-01T12:00:00.000Z',
          },
          {
            'id': 'pay-2',
            'method': 'cash',
            'amount': -50.0,
            'recorded_by': {'id': 'staff-uuid', 'display_name': 'Reception'},
            'recorded_at': '2026-06-01T12:30:00.000Z',
          },
        ],
      });

      expect(item, isNotNull);
      expect(item!.payments, hasLength(2));
      expect(item.paidAmount.wireValue, '75.00');
      expect(item.balance.wireValue, '50.00');
    });
  });
}
