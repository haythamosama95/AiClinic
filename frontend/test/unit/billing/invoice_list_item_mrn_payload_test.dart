import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal invoice list row for MRN parser tests (US5).
Map<String, dynamic> invoiceListRow({
  String? patientMrn,
  String? mrnAlias,
}) {
  return {
    'id': 'inv-1',
    'status': 'issued',
    'subtotal': '100.00',
    'discount_amount': '0.00',
    'insurance_covered_amount': '0.00',
    'paid_amount': '0.00',
    'balance': '100.00',
    'created_at': '2026-06-01T10:00:00.000Z',
    if (patientMrn != null) 'patient_mrn': patientMrn,
    if (mrnAlias != null) 'mrn': mrnAlias,
  };
}

/// Minimal get_invoice_detail envelope for MRN parser tests (US5).
Map<String, dynamic> invoiceDetailEnvelope({
  String? mrn,
  String? patientMrnAlias,
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
    },
    'items': const [],
    'payments': const [],
    'patient': {
      'id': 'patient-1',
      'display_name': 'Test Patient',
      if (mrn != null) 'mrn': mrn,
      if (patientMrnAlias != null) 'patient_mrn': patientMrnAlias,
    },
    'branch': {'id': 'branch-1', 'code': 'MAIN', 'name': 'Main'},
  };
}

void main() {
  group('InvoiceListItem MRN parsing (US5)', () {
    test('fromRow parses patient_mrn from list_invoices payload', () {
      final item = InvoiceListItem.fromRow(invoiceListRow(patientMrn: 'MRN-000042'));

      expect(item, isNotNull);
      expect(item!.patientMrn, 'MRN-000042');
    });

    test('fromRow falls back to mrn alias when patient_mrn absent', () {
      final item = InvoiceListItem.fromRow(invoiceListRow(mrnAlias: 'MRN-000099'));

      expect(item!.patientMrn, 'MRN-000099');
    });

    test('prefers patient_mrn over mrn when both present', () {
      final item = InvoiceListItem.fromRow(
        invoiceListRow(patientMrn: 'MRN-000001', mrnAlias: 'MRN-000002'),
      );

      expect(item!.patientMrn, 'MRN-000001');
    });

    test('fromRow leaves patientMrn null when patient_mrn absent', () {
      final item = InvoiceListItem.fromRow(invoiceListRow());

      expect(item!.patientMrn, isNull);
    });
  });

  group('InvoiceDetail MRN parsing (US5)', () {
    test('fromRpcData parses mrn from get_invoice_detail patient sub-object', () {
      final detail = InvoiceDetail.fromRpcData(
        invoiceDetailEnvelope(mrn: 'MRN-000042'),
      );

      expect(detail, isNotNull);
      expect(detail!.patientMrn, 'MRN-000042');
    });

    test('fromRpcData falls back to patient_mrn alias', () {
      final detail = InvoiceDetail.fromRpcData(
        invoiceDetailEnvelope(patientMrnAlias: 'MRN-000088'),
      );

      expect(detail!.patientMrn, 'MRN-000088');
    });

    test('prefers mrn over patient_mrn when both present', () {
      final detail = InvoiceDetail.fromRpcData(
        invoiceDetailEnvelope(mrn: 'MRN-000001', patientMrnAlias: 'MRN-000002'),
      );

      expect(detail!.patientMrn, 'MRN-000001');
    });
  });
}
