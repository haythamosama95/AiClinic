import 'package:ai_clinic/features/billing/domain/discount_kind.dart';
import 'package:ai_clinic/features/billing/domain/discount_scope.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
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

    test('tryParse trims whitespace', () {
      expect(InvoiceStatus.tryParse('  issued  '), InvoiceStatus.issued);
      expect(InvoiceStatus.tryParse('\tpartially_paid\n'), InvoiceStatus.partiallyPaid);
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

    test('wireValue strings match PostgreSQL enum', () {
      expect(InvoiceStatus.draft.wireValue, 'draft');
      expect(InvoiceStatus.issued.wireValue, 'issued');
      expect(InvoiceStatus.partiallyPaid.wireValue, 'partially_paid');
      expect(InvoiceStatus.paid.wireValue, 'paid');
      expect(InvoiceStatus.voided.wireValue, 'voided');
    });

    test('label for all values', () {
      expect(InvoiceStatus.draft.label, 'Draft');
      expect(InvoiceStatus.issued.label, 'Issued');
      expect(InvoiceStatus.partiallyPaid.label, 'Partially paid');
      expect(InvoiceStatus.paid.label, 'Paid');
      expect(InvoiceStatus.voided.label, 'Voided');
    });

    test('isDraft and isTerminal flags', () {
      expect(InvoiceStatus.draft.isDraft, isTrue);
      expect(InvoiceStatus.issued.isDraft, isFalse);
      expect(InvoiceStatus.paid.isTerminal, isTrue);
      expect(InvoiceStatus.voided.isTerminal, isTrue);
      expect(InvoiceStatus.partiallyPaid.isTerminal, isFalse);
    });

    test('isTerminal is false for non-terminal values', () {
      expect(InvoiceStatus.draft.isTerminal, isFalse);
      expect(InvoiceStatus.issued.isTerminal, isFalse);
      expect(InvoiceStatus.partiallyPaid.isTerminal, isFalse);
    });

    test('isVoided is true only for voided', () {
      expect(InvoiceStatus.voided.isVoided, isTrue);
      expect(InvoiceStatus.draft.isVoided, isFalse);
      expect(InvoiceStatus.issued.isVoided, isFalse);
      expect(InvoiceStatus.partiallyPaid.isVoided, isFalse);
      expect(InvoiceStatus.paid.isVoided, isFalse);
    });

    test('isVoidable is true only for issued and partially paid', () {
      expect(InvoiceStatus.issued.isVoidable, isTrue);
      expect(InvoiceStatus.partiallyPaid.isVoidable, isTrue);
      expect(InvoiceStatus.draft.isVoidable, isFalse);
      expect(InvoiceStatus.paid.isVoidable, isFalse);
      expect(InvoiceStatus.voided.isVoidable, isFalse);
    });
  });

  group('PaymentMethod', () {
    test('tryParse accepts wire values', () {
      expect(PaymentMethod.tryParse('bank_transfer'), PaymentMethod.bankTransfer);
      expect(PaymentMethod.tryParse('insurance_settlement'), PaymentMethod.insuranceSettlement);
    });

    test('tryParse matrix for null empty unknown and whitespace', () {
      expect(PaymentMethod.tryParse(null), isNull);
      expect(PaymentMethod.tryParse(''), isNull);
      expect(PaymentMethod.tryParse('   '), isNull);
      expect(PaymentMethod.tryParse('cheque'), isNull);
      expect(PaymentMethod.tryParse('  cash  '), PaymentMethod.cash);
      expect(PaymentMethod.tryParse('CARD'), PaymentMethod.card);
    });

    test('wireValue strings match PostgreSQL enum', () {
      expect(PaymentMethod.cash.wireValue, 'cash');
      expect(PaymentMethod.card.wireValue, 'card');
      expect(PaymentMethod.bankTransfer.wireValue, 'bank_transfer');
      expect(PaymentMethod.insuranceSettlement.wireValue, 'insurance_settlement');
    });

    test('label for all values', () {
      expect(PaymentMethod.cash.label, 'Cash');
      expect(PaymentMethod.card.label, 'Card');
      expect(PaymentMethod.bankTransfer.label, 'Bank transfer');
      expect(PaymentMethod.insuranceSettlement.label, 'Insurance settlement');
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

    test('wireValue strings', () {
      expect(DiscountKind.percentage.wireValue, 'percentage');
      expect(DiscountKind.fixed.wireValue, 'fixed');
    });

    test('label for all values', () {
      expect(DiscountKind.percentage.label, 'Percentage');
      expect(DiscountKind.fixed.label, 'Fixed amount');
    });
  });

  group('DiscountScope', () {
    test('label for both values', () {
      expect(DiscountScope.line.label, 'Line item');
      expect(DiscountScope.invoice.label, 'Invoice total');
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

    test('fromRow parses recorded_by as plain scalar string id', () {
      final payment = Payment.fromRow({
        'id': 'pay-1',
        'method': 'cash',
        'amount': '50.00',
        'recorded_by': 'staff-uuid',
        'recorded_at': '2026-06-01T12:00:00.000Z',
      });

      expect(payment, isNotNull);
      expect(payment!.recordedById, 'staff-uuid');
      expect(payment.recordedByDisplayName, isNull);
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

    test('fromRow rejects invalid method', () {
      expect(
        Payment.fromRow({
          'id': 'pay-1',
          'method': 'cheque',
          'amount': '50.00',
          'recorded_by': 'staff-uuid',
          'recorded_at': '2026-06-01T12:00:00.000Z',
        }),
        isNull,
      );
    });

    test('fromRow rejects invalid amount', () {
      expect(
        Payment.fromRow({
          'id': 'pay-1',
          'method': 'cash',
          'amount': 'not-money',
          'recorded_by': 'staff-uuid',
          'recorded_at': '2026-06-01T12:00:00.000Z',
        }),
        isNull,
      );
    });

    test('fromRow rejects invalid recorded_at', () {
      expect(
        Payment.fromRow({
          'id': 'pay-1',
          'method': 'cash',
          'amount': '50.00',
          'recorded_by': 'staff-uuid',
          'recorded_at': 'not-a-date',
        }),
        isNull,
      );
    });

    test('fromRow parses note', () {
      final payment = Payment.fromRow({
        'id': 'pay-1',
        'method': 'cash',
        'amount': '50.00',
        'note': 'Partial payment',
        'recorded_by': 'staff-uuid',
        'recorded_at': '2026-06-01T12:00:00.000Z',
      });

      expect(payment!.note, 'Partial payment');
    });

    test('fromRow parses amount supplied as num', () {
      final payment = Payment.fromRow({
        'id': 'pay-1',
        'method': 'cash',
        'amount': 75.5,
        'recorded_by': 'staff-uuid',
        'recorded_at': '2026-06-01T12:00:00.000Z',
      });

      expect(payment!.amount.wireValue, '75.50');
    });

    test('isRefund is true for negative amount', () {
      final payment = Payment.fromRow({
        'id': 'pay-1',
        'method': 'cash',
        'amount': '-25.00',
        'recorded_by': 'staff-uuid',
        'recorded_at': '2026-06-01T12:00:00.000Z',
      });

      expect(payment!.isRefund, isTrue);
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
              'date_of_birth': '1990-05-15',
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
      expect(detail.patientDateOfBirth, DateTime.utc(1990, 5, 15));
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
      expect(detail.patientDateOfBirth, isNull);
      expect(detail.visitSummary, isNull);
    });

    test('fromRpcData returns null for null input', () {
      expect(InvoiceDetail.fromRpcData(null), isNull);
    });

    test('fromRpcData returns null when invoice key is missing', () {
      expect(InvoiceDetail.fromRpcData({'items': []}), isNull);
    });

    test('fromRpcData rejects missing id', () {
      expect(
        InvoiceDetail.fromRpcData(minimalEnvelope(invoiceOverrides: {'id': null})),
        isNull,
      );
    });

    test('fromRpcData rejects missing status', () {
      expect(
        InvoiceDetail.fromRpcData(minimalEnvelope(invoiceOverrides: {'status': 'cancelled'})),
        isNull,
      );
    });

    test('fromRpcData rejects missing branch_id', () {
      expect(
        InvoiceDetail.fromRpcData(minimalEnvelope(invoiceOverrides: {'branch_id': ''})),
        isNull,
      );
    });

    test('fromRpcData rejects missing patient_id', () {
      expect(
        InvoiceDetail.fromRpcData(minimalEnvelope(invoiceOverrides: {'patient_id': null})),
        isNull,
      );
    });

    test('fromRpcData rejects missing visit_id', () {
      expect(
        InvoiceDetail.fromRpcData(minimalEnvelope(invoiceOverrides: {'visit_id': ''})),
        isNull,
      );
    });

    test('fromRpcData rejects missing updated_at', () {
      expect(
        InvoiceDetail.fromRpcData(minimalEnvelope(invoiceOverrides: {'updated_at': null})),
        isNull,
      );
    });

    test('fromRpcData rejects invalid updated_at', () {
      expect(
        InvoiceDetail.fromRpcData(minimalEnvelope(invoiceOverrides: {'updated_at': 'bad'})),
        isNull,
      );
    });

    test('fromRpcData rejects missing subtotal', () {
      expect(
        InvoiceDetail.fromRpcData(minimalEnvelope(invoiceOverrides: {'subtotal': null})),
        isNull,
      );
    });

    test('fromRpcData rejects missing discount_amount', () {
      expect(
        InvoiceDetail.fromRpcData(minimalEnvelope(invoiceOverrides: {'discount_amount': null})),
        isNull,
      );
    });

    test('fromRpcData rejects missing insurance_covered_amount', () {
      expect(
        InvoiceDetail.fromRpcData(minimalEnvelope(invoiceOverrides: {'insurance_covered_amount': null})),
        isNull,
      );
    });

    test('fromRpcData rejects missing balance', () {
      expect(
        InvoiceDetail.fromRpcData(minimalEnvelope(invoiceOverrides: {'balance': null})),
        isNull,
      );
    });

    test('fromRpcData parses items list', () {
      final detail = InvoiceDetail.fromRpcData(
        minimalEnvelope(
          envelopeOverrides: {
            'items': [
              {
                'id': 'item-1',
                'description': 'Consultation',
                'quantity': '1',
                'unit_price': '50.00',
                'line_subtotal': '50.00',
                'line_discount_amount': '0.00',
                'line_total': '50.00',
              },
            ],
          },
        ),
      );

      expect(detail!.items, hasLength(1));
      expect(detail.items.first.description, 'Consultation');
    });

    test('fromRpcData parses payments list', () {
      final detail = InvoiceDetail.fromRpcData(
        minimalEnvelope(
          envelopeOverrides: {
            'payments': [
              {
                'id': 'pay-1',
                'method': 'cash',
                'amount': '25.00',
                'recorded_by': 'staff-1',
                'recorded_at': '2026-06-01T12:00:00.000Z',
              },
            ],
          },
        ),
      );

      expect(detail!.payments, hasLength(1));
      expect(detail.payments.first.amount.wireValue, '25.00');
    });

    test('fromRpcData uses voided_by_name when present on invoice', () {
      final detail = InvoiceDetail.fromRpcData(
        minimalEnvelope(invoiceOverrides: {'voided_by_name': 'Admin User'}),
      );

      expect(detail!.voidedByName, 'Admin User');
    });

    test('fromRpcData falls back to voided_by map on invoice', () {
      final detail = InvoiceDetail.fromRpcData(
        minimalEnvelope(
          invoiceOverrides: {
            'voided_by': {'id': 'staff-1', 'display_name': 'Front Desk'},
          },
        ),
      );

      expect(detail!.voidedByName, 'Front Desk');
    });

    test('fromRpcData falls back to voided_by map on data envelope', () {
      final detail = InvoiceDetail.fromRpcData(
        minimalEnvelope(
          envelopeOverrides: {
            'voided_by': {'id': 'staff-2', 'full_name': 'Billing Lead'},
          },
        ),
      );

      expect(detail!.voidedByName, 'Billing Lead');
    });

    test('fromRpcData defaults currency to USD when absent', () {
      final detail = InvoiceDetail.fromRpcData(minimalEnvelope());
      expect(detail!.currency, 'USD');
    });

    test('created_at falls back to updatedAt when absent', () {
      final detail = InvoiceDetail.fromRpcData(minimalEnvelope());
      expect(detail!.createdAt, detail.updatedAt);
    });

    test('VisitSummary.fromRpcData rejects partial visit payloads', () {
      expect(VisitSummary.fromRpcData({'visit_date': '2026-06-01', 'doctor_name': 'Dr. Smith'}), isNull);
    });

    test('VisitSummary.fromRpcData rejects non-Map input', () {
      expect(VisitSummary.fromRpcData('visit'), isNull);
      expect(VisitSummary.fromRpcData(null), isNull);
    });

    test('VisitSummary.fromRpcData parses visit_date key', () {
      final summary = VisitSummary.fromRpcData({
        'visit_date': '2026-06-01T15:30:00.000Z',
        'doctor_name': 'Dr. Smith',
        'branch_name': 'Main',
      });

      expect(summary!.date, DateTime.utc(2026, 6, 1));
    });

    test('VisitSummary.fromRpcData parses date key fallback', () {
      final summary = VisitSummary.fromRpcData({
        'date': '2026-06-02',
        'doctor_name': 'Dr. Smith',
        'branch_name': 'Main',
      });

      expect(summary!.date, DateTime.utc(2026, 6, 2));
    });

    test('VisitSummary.fromRpcData parses started_at key fallback', () {
      final summary = VisitSummary.fromRpcData({
        'started_at': '2026-06-03T08:00:00.000Z',
        'doctor_name': 'Dr. Smith',
        'branch_name': 'Main',
      });

      expect(summary!.date, DateTime.utc(2026, 6, 3));
    });

    test('VisitSummary.fromRpcData uses doctor and branch key fallbacks', () {
      final summary = VisitSummary.fromRpcData({
        'visit_date': '2026-06-01',
        'doctor': 'Dr. Jones',
        'branch': 'East Wing',
      });

      expect(summary!.doctor, 'Dr. Jones');
      expect(summary.branch, 'East Wing');
    });
  });

  group('InvoiceListItem', () {
    Map<String, dynamic> minimalListRow({
      Map<String, dynamic>? overrides,
    }) {
      return {
        'id': 'inv-1',
        'status': 'issued',
        'subtotal': '100.00',
        'discount_amount': '10.00',
        'insurance_covered_amount': '0.00',
        'paid_amount': '0.00',
        'balance': '90.00',
        'created_at': '2026-06-01T10:00:00.000Z',
        ...?overrides,
      };
    }

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

    test('displayTotal is subtotal minus discountAmount', () {
      final item = InvoiceListItem.fromRow(minimalListRow());
      expect(item!.displayTotal, '90.00');
    });

    test('copyWith replaces payments', () {
      final item = InvoiceListItem.fromRow(minimalListRow())!;
      final payment = Payment(
        id: 'pay-1',
        method: PaymentMethod.cash,
        amount: Money.parse('10.00'),
        recordedById: 'staff-1',
        recordedAt: DateTime.parse('2026-06-01T12:00:00.000Z'),
      );

      final updated = item.copyWith(payments: [payment]);
      expect(updated.payments, hasLength(1));
      expect(updated.payments.first.id, 'pay-1');
    });

    test('fromRow rejects missing id', () {
      expect(InvoiceListItem.fromRow(minimalListRow(overrides: {'id': null})), isNull);
    });

    test('fromRow rejects missing status', () {
      expect(InvoiceListItem.fromRow(minimalListRow(overrides: {'status': 'bogus'})), isNull);
    });

    test('fromRow rejects missing created_at', () {
      expect(InvoiceListItem.fromRow(minimalListRow(overrides: {'created_at': null})), isNull);
    });

    test('fromRow rejects invalid created_at', () {
      expect(InvoiceListItem.fromRow(minimalListRow(overrides: {'created_at': 'bad'})), isNull);
    });

    test('fromRow rejects missing subtotal', () {
      expect(InvoiceListItem.fromRow(minimalListRow(overrides: {'subtotal': null})), isNull);
    });

    test('fromRow rejects missing discount_amount', () {
      expect(InvoiceListItem.fromRow(minimalListRow(overrides: {'discount_amount': null})), isNull);
    });

    test('fromRow rejects missing insurance_covered_amount', () {
      expect(
        InvoiceListItem.fromRow(minimalListRow(overrides: {'insurance_covered_amount': null})),
        isNull,
      );
    });

    test('fromRow rejects missing paid_amount', () {
      expect(InvoiceListItem.fromRow(minimalListRow(overrides: {'paid_amount': null})), isNull);
    });

    test('fromRow rejects missing balance', () {
      expect(InvoiceListItem.fromRow(minimalListRow(overrides: {'balance': null})), isNull);
    });

    test('fromRow defaults currency to USD when absent', () {
      final item = InvoiceListItem.fromRow(minimalListRow());
      expect(item!.currency, 'USD');
    });

    test('fromRow defaults currency to USD when empty', () {
      final item = InvoiceListItem.fromRow(minimalListRow(overrides: {'currency': ''}));
      expect(item!.currency, 'USD');
    });

    test('fromRow uppercases currency', () {
      final item = InvoiceListItem.fromRow(minimalListRow(overrides: {'currency': 'egp'}));
      expect(item!.currency, 'EGP');
    });

    test('fromRow parses issued_at', () {
      final item = InvoiceListItem.fromRow(
        minimalListRow(overrides: {'issued_at': '2026-06-02T09:00:00.000Z'}),
      );

      expect(item!.issuedAt, DateTime.parse('2026-06-02T09:00:00.000Z'));
    });

    test('fromRow treats non-List payments as empty', () {
      final item = InvoiceListItem.fromRow(minimalListRow(overrides: {'payments': 'bad'}));
      expect(item!.payments, isEmpty);
    });

    test('fromRow skips invalid payment rows', () {
      final item = InvoiceListItem.fromRow(
        minimalListRow(
          overrides: {
            'payments': [
              'not-a-map',
              {
                'id': 'pay-1',
                'method': 'cash',
                'amount': '10.00',
                'recorded_by': 'staff-1',
                'recorded_at': '2026-06-01T12:00:00.000Z',
              },
            ],
          },
        ),
      );

      expect(item!.payments, hasLength(1));
    });
  });
}
