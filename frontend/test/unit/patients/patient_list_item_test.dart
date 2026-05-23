import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientListItem.fromRow', () {
    test('parses complete search result row', () {
      final item = PatientListItem.fromRow({
        'id': 'p1',
        'full_name': '  Ahmed Hassan  ',
        'phone': '201234567890',
        'date_of_birth': '1990-05-15',
        'branch_id': 'b1',
        'branch_name': 'Main Clinic',
      });

      expect(item, isNotNull);
      expect(item!.fullName, 'Ahmed Hassan');
      expect(item.phone, '201234567890');
      expect(item.dateOfBirth, DateTime(1990, 5, 15));
      expect(item.registeringBranchId, 'b1');
      expect(item.registeringBranchName, 'Main Clinic');
    });

    test('allows null optional fields', () {
      final item = PatientListItem.fromRow({
        'id': 'p1',
        'full_name': 'No Phone',
        'branch_id': 'b1',
        'branch_name': 'Branch',
      });

      expect(item!.phone, isNull);
      expect(item.dateOfBirth, isNull);
    });

    test('returns null when required fields missing or blank', () {
      expect(PatientListItem.fromRow({'id': '', 'full_name': 'X', 'branch_id': 'b', 'branch_name': 'B'}), isNull);
      expect(PatientListItem.fromRow({'id': 'p', 'full_name': '  ', 'branch_id': 'b', 'branch_name': 'B'}), isNull);
      expect(PatientListItem.fromRow({'id': 'p', 'full_name': 'X', 'branch_id': '', 'branch_name': 'B'}), isNull);
      expect(PatientListItem.fromRow({'id': 'p', 'full_name': 'X', 'branch_id': 'b', 'branch_name': '  '}), isNull);
    });

    test('strips blank optional strings', () {
      final item = PatientListItem.fromRow({
        'id': 'p1',
        'full_name': 'X',
        'phone': '   ',
        'branch_id': 'b1',
        'branch_name': 'Branch',
      });

      expect(item!.phone, isNull);
    });

    test('edge case: invalid date_of_birth yields null DOB without failing', () {
      final item = PatientListItem.fromRow({
        'id': 'p1',
        'full_name': 'X',
        'date_of_birth': 'not-a-date',
        'branch_id': 'b1',
        'branch_name': 'Branch',
      });

      expect(item!.dateOfBirth, isNull);
    });

    test('edge case: DateTime input normalizes to date-only', () {
      final item = PatientListItem.fromRow({
        'id': 'p1',
        'full_name': 'X',
        'date_of_birth': DateTime(2000, 1, 2, 15, 30),
        'branch_id': 'b1',
        'branch_name': 'Branch',
      });

      expect(item!.dateOfBirth, DateTime(2000, 1, 2));
    });

    test('stupid user: unexpected types coerced via toString', () {
      final item = PatientListItem.fromRow({'id': 12345, 'full_name': 999, 'branch_id': true, 'branch_name': 'Branch'});

      expect(item!.id, '12345');
      expect(item.fullName, '999');
      expect(item.registeringBranchId, 'true');
    });
  });

  group('PatientListItem equality', () {
    test('copyWith preserves unchanged fields', () {
      const original = PatientListItem(
        id: 'p1',
        fullName: 'A',
        registeringBranchId: 'b1',
        registeringBranchName: 'Main',
      );
      final updated = original.copyWith(fullName: 'B');

      expect(updated.fullName, 'B');
      expect(updated.id, original.id);
      expect(original == updated, isFalse);
    });
  });
}
