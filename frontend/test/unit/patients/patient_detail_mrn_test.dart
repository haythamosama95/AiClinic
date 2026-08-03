import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientDetail MRN parsing (US4)', () {
    test('fromRow parses mrn from row key', () {
      final detail = PatientDetail.fromRow({
        'id': 'p1',
        'full_name': 'Sara Ali',
        'mrn': 'MRN-000042',
        'branch_id': 'b1',
        'branch_name': 'Downtown',
        'created_at': '2026-05-23T10:00:00.000Z',
        'updated_at': '2026-05-23T11:30:00.000Z',
      });

      expect(detail, isNotNull);
      expect(detail!.mrn, 'MRN-000042');
    });

    test('fromRow falls back to patient_mrn alias', () {
      final detail = PatientDetail.fromRow({
        'id': 'p1',
        'full_name': 'Sara Ali',
        'patient_mrn': 'MRN-000099',
        'branch_id': 'b1',
        'branch_name': 'Downtown',
        'created_at': '2026-05-23T10:00:00.000Z',
        'updated_at': '2026-05-23T11:30:00.000Z',
      });

      expect(detail!.mrn, 'MRN-000099');
    });

    test('blank mrn values are treated as null', () {
      final detail = PatientDetail.fromRow({
        'id': 'p1',
        'full_name': 'Sara Ali',
        'mrn': '  ',
        'branch_id': 'b1',
        'branch_name': 'Downtown',
        'created_at': '2026-05-23T10:00:00.000Z',
        'updated_at': '2026-05-23T11:30:00.000Z',
      });

      expect(detail!.mrn, isNull);
    });
  });
}
