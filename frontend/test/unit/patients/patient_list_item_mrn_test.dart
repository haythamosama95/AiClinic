import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientListItem MRN parsing (US3)', () {
    test('fromRow parses mrn from row key', () {
      final item = PatientListItem.fromRow({
        'id': 'p1',
        'full_name': 'Ahmed Hassan',
        'mrn': 'MRN-000042',
        'branch_id': 'b1',
        'branch_name': 'Main',
      });

      expect(item, isNotNull);
      expect(item!.mrn, 'MRN-000042');
    });

    test('fromRow falls back to patient_mrn alias', () {
      final item = PatientListItem.fromRow({
        'id': 'p1',
        'full_name': 'Ahmed Hassan',
        'patient_mrn': 'MRN-000099',
        'branch_id': 'b1',
        'branch_name': 'Main',
      });

      expect(item!.mrn, 'MRN-000099');
    });

    test('prefers mrn over patient_mrn when both present', () {
      final item = PatientListItem.fromRow({
        'id': 'p1',
        'full_name': 'Ahmed Hassan',
        'mrn': 'MRN-000001',
        'patient_mrn': 'MRN-000002',
        'branch_id': 'b1',
        'branch_name': 'Main',
      });

      expect(item!.mrn, 'MRN-000001');
    });

    test('blank mrn values are treated as null', () {
      final item = PatientListItem.fromRow({
        'id': 'p1',
        'full_name': 'Ahmed Hassan',
        'mrn': '   ',
        'branch_id': 'b1',
        'branch_name': 'Main',
      });

      expect(item!.mrn, isNull);
    });
  });

  group('PatientListUiState row flow (US3)', () {
    test('MRN flows from list item into table rows', () {
      const item = PatientListItem(
        id: 'p1',
        fullName: 'Ahmed Hassan',
        mrn: 'MRN-000042',
        registeringBranchId: 'b1',
        registeringBranchName: 'Main',
      );

      final rows = PatientTableRow.fromItems([item]);

      expect(rows, hasLength(1));
      expect(rows.first.item.mrn, 'MRN-000042');
    });
  });
}
