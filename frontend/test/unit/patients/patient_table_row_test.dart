import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientTableRow', () {
    test('exposes the underlying list item', () {
      final item = PatientListItem(
        id: 'p1',
        fullName: 'Sara Ali',
        registeringBranchId: 'b1',
        registeringBranchName: 'Main',
      );
      final row = PatientTableRow(item: item);

      expect(row.item, item);
    });

    test('fromItems maps each list item to a row', () {
      final items = [
        PatientListItem(
          id: 'p1',
          fullName: 'Sara Ali',
          registeringBranchId: 'b1',
          registeringBranchName: 'Main',
        ),
        PatientListItem(
          id: 'p2',
          fullName: 'Omar Hassan',
          registeringBranchId: 'b1',
          registeringBranchName: 'Main',
        ),
      ];

      final rows = PatientTableRow.fromItems(items);

      expect(rows, hasLength(2));
      expect(rows[0].item.id, 'p1');
      expect(rows[1].item.id, 'p2');
    });
  });
}
