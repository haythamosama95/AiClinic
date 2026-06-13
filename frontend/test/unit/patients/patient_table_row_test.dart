import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientTableRow', () {
    test('ageGenderLabel shows age and gender when both are available', () {
      withClock(Clock.fixed(DateTime(2026, 6, 13)), () {
        final row = PatientTableRow(
          item: PatientListItem(
            id: 'p1',
            fullName: 'Sara Ali',
            registeringBranchId: 'b1',
            registeringBranchName: 'Main',
            dateOfBirth: DateTime.utc(1990, 5, 15),
            gender: PatientGender.female,
          ),
        );

        expect(row.ageGenderLabel, '36, Female');
      });
    });

    test('ageGenderLabel shows gender only when DOB is missing', () {
      const row = PatientTableRow(
        item: PatientListItem(
          id: 'p1',
          fullName: 'Sara Ali',
          registeringBranchId: 'b1',
          registeringBranchName: 'Main',
          gender: PatientGender.male,
        ),
      );

      expect(row.ageGenderLabel, 'Male');
    });

    test('lastVisitAt and nextAppointmentAt come from list item', () {
      final lastVisit = DateTime.utc(2026, 1, 10);
      final nextAppointment = DateTime.parse('2026-06-20T14:30:00.000Z');
      final row = PatientTableRow(
        item: PatientListItem(
          id: 'p1',
          fullName: 'Sara Ali',
          registeringBranchId: 'b1',
          registeringBranchName: 'Main',
          lastVisitAt: lastVisit,
          nextAppointmentAt: nextAppointment,
        ),
      );

      expect(row.lastVisitAt, lastVisit);
      expect(row.nextAppointmentAt, nextAppointment);
    });
  });

  group('PatientTableRow age', () {
    test('subtracts one year before birthday', () {
      withClock(Clock.fixed(DateTime(2026, 6, 13)), () {
        final row = PatientTableRow(
          item: PatientListItem(
            id: 'p1',
            fullName: 'Child',
            registeringBranchId: 'b1',
            registeringBranchName: 'Main',
            dateOfBirth: DateTime.utc(1990, 12, 31),
          ),
        );

        expect(row.age, 35);
      });
    });

    test('includes birthday on the exact date', () {
      withClock(Clock.fixed(DateTime(2026, 6, 13)), () {
        final row = PatientTableRow(
          item: PatientListItem(
            id: 'p1',
            fullName: 'Child',
            registeringBranchId: 'b1',
            registeringBranchName: 'Main',
            dateOfBirth: DateTime.utc(1990, 6, 13),
          ),
        );

        expect(row.age, 36);
      });
    });
  });
}
