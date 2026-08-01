import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
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
        'gender': 'male',
        'last_visit_at': '2026-01-10',
        'next_appointment_at': '2026-06-20T14:30:00.000Z',
        'branch_id': 'b1',
        'branch_name': 'Main Clinic',
      });

      expect(item, isNotNull);
      expect(item!.fullName, 'Ahmed Hassan');
      expect(item.phone, '201234567890');
      expect(item.dateOfBirth, DateTime.utc(1990, 5, 15));
      expect(item.gender, PatientGender.male);
      expect(item.lastVisitAt, DateTime.utc(2026, 1, 10));
      expect(item.nextAppointmentAt, DateTime.parse('2026-06-20T14:30:00.000Z'));
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

      expect(item!.dateOfBirth, DateTime.utc(2000, 1, 2));
    });

    test('stupid user: unexpected types coerced via toString', () {
      final item = PatientListItem.fromRow({'id': 12345, 'full_name': 999, 'branch_id': true, 'branch_name': 'Branch'});

      expect(item!.id, '12345');
      expect(item.fullName, '999');
      expect(item.registeringBranchId, 'true');
    });
  });

  group('PatientListItem equality', () {
    const base = PatientListItem(
      id: 'p1',
      mrn: 'MRN-000001',
      fullName: 'Ahmed',
      phone: '201000000001',
      dateOfBirth: null,
      gender: PatientGender.male,
      lastVisitAt: null,
      nextAppointmentAt: null,
      registeringBranchId: 'b1',
      registeringBranchName: 'Main',
    );

    test('trivial: equal instances share hashCode', () {
      const a = base;
      const b = base;

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('edge case: differing id is unequal', () {
      expect(base.copyWith(id: 'p2') == base, isFalse);
    });

    test('edge case: differing mrn is unequal', () {
      expect(base.copyWith(mrn: 'MRN-000002') == base, isFalse);
    });

    test('edge case: differing fullName is unequal', () {
      expect(base.copyWith(fullName: 'Sara') == base, isFalse);
    });

    test('edge case: differing phone is unequal', () {
      expect(base.copyWith(phone: '201999999999') == base, isFalse);
    });

    test('edge case: differing dateOfBirth is unequal', () {
      expect(
        base.copyWith(dateOfBirth: DateTime.utc(1990, 1, 1)) == base,
        isFalse,
      );
    });

    test('edge case: differing gender is unequal', () {
      expect(base.copyWith(gender: PatientGender.female) == base, isFalse);
    });

    test('edge case: differing lastVisitAt is unequal', () {
      expect(
        base.copyWith(lastVisitAt: DateTime.utc(2026, 1, 1)) == base,
        isFalse,
      );
    });

    test('edge case: differing nextAppointmentAt is unequal', () {
      expect(
        base.copyWith(nextAppointmentAt: DateTime.utc(2026, 6, 1)) == base,
        isFalse,
      );
    });

    test('edge case: differing registeringBranchId is unequal', () {
      expect(base.copyWith(registeringBranchId: 'b2') == base, isFalse);
    });

    test('edge case: differing registeringBranchName is unequal', () {
      expect(base.copyWith(registeringBranchName: 'South') == base, isFalse);
    });

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

    test('advanced: omitted nullable fields are preserved', () {
      final withPhone = base.copyWith(phone: '201111111111');
      final updated = withPhone.copyWith(fullName: 'Updated');

      expect(updated.phone, '201111111111');
      expect(updated.mrn, base.mrn);
    });

    test('advanced: explicitly clears nullable fields with null', () {
      final withOptionals = base.copyWith(
        mrn: 'MRN-000010',
        phone: '201111111111',
        dateOfBirth: DateTime.utc(1990, 5, 15),
        gender: PatientGender.female,
        lastVisitAt: DateTime.utc(2026, 1, 1),
        nextAppointmentAt: DateTime.utc(2026, 6, 1),
      );

      final cleared = withOptionals.copyWith(
        mrn: null,
        phone: null,
        dateOfBirth: null,
        gender: null,
        lastVisitAt: null,
        nextAppointmentAt: null,
      );

      expect(cleared.mrn, isNull);
      expect(cleared.phone, isNull);
      expect(cleared.dateOfBirth, isNull);
      expect(cleared.gender, isNull);
      expect(cleared.lastVisitAt, isNull);
      expect(cleared.nextAppointmentAt, isNull);
      expect(cleared.fullName, withOptionals.fullName);
    });
  });
}
