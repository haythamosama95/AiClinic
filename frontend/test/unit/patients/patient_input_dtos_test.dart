import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreatePatientInput', () {
    test('constructs with required fields only', () {
      const input = CreatePatientInput(
        activeBranchId: 'b1',
        fullName: 'Ahmed',
        phone: '201000000001',
      );

      expect(input.activeBranchId, 'b1');
      expect(input.fullName, 'Ahmed');
      expect(input.phone, '201000000001');
      expect(input.dateOfBirth, isNull);
      expect(input.gender, isNull);
      expect(input.maritalStatus, isNull);
      expect(input.notes, isNull);
      expect(input.acknowledgeDuplicate, isFalse);
    });

    test('constructs with all optional fields', () {
      final input = CreatePatientInput(
        activeBranchId: 'b1',
        fullName: 'Sara Ali',
        phone: '201999999999',
        dateOfBirth: DateTime(1990, 5, 15),
        gender: PatientGender.female,
        maritalStatus: PatientMaritalStatus.married,
        notes: 'Allergic to penicillin',
        acknowledgeDuplicate: true,
      );

      expect(input.dateOfBirth, DateTime(1990, 5, 15));
      expect(input.gender, PatientGender.female);
      expect(input.maritalStatus, PatientMaritalStatus.married);
      expect(input.notes, 'Allergic to penicillin');
      expect(input.acknowledgeDuplicate, isTrue);
    });

    test('acknowledgeDuplicate defaults to false', () {
      const input = CreatePatientInput(
        activeBranchId: 'b1',
        fullName: 'Test',
        phone: '123',
      );

      expect(input.acknowledgeDuplicate, isFalse);
    });
  });

  group('UpdatePatientInput', () {
    test('constructs with required fields only', () {
      final input = UpdatePatientInput(
        patientId: 'p1',
        fullName: 'Updated Name',
        expectedUpdatedAt: DateTime.utc(2026, 1, 2, 9, 30),
      );

      expect(input.patientId, 'p1');
      expect(input.fullName, 'Updated Name');
      expect(input.expectedUpdatedAt, DateTime.utc(2026, 1, 2, 9, 30));
      expect(input.phone, isNull);
      expect(input.dateOfBirth, isNull);
      expect(input.gender, isNull);
      expect(input.maritalStatus, isNull);
      expect(input.notes, isNull);
      expect(input.acknowledgeDuplicate, isFalse);
    });

    test('constructs with all optional fields', () {
      final input = UpdatePatientInput(
        patientId: 'p1',
        fullName: 'Sara Ali',
        expectedUpdatedAt: DateTime.utc(2026, 1, 2),
        phone: '201999999999',
        dateOfBirth: DateTime(1985, 3, 20),
        gender: PatientGender.male,
        maritalStatus: PatientMaritalStatus.divorced,
        notes: 'Updated notes',
        acknowledgeDuplicate: true,
      );

      expect(input.phone, '201999999999');
      expect(input.dateOfBirth, DateTime(1985, 3, 20));
      expect(input.gender, PatientGender.male);
      expect(input.maritalStatus, PatientMaritalStatus.divorced);
      expect(input.notes, 'Updated notes');
      expect(input.acknowledgeDuplicate, isTrue);
    });

    test('acknowledgeDuplicate defaults to false', () {
      final input = UpdatePatientInput(
        patientId: 'p1',
        fullName: 'Test',
        expectedUpdatedAt: DateTime.utc(2026),
      );

      expect(input.acknowledgeDuplicate, isFalse);
    });

    test('expectedUpdatedAt preserves UTC timezone', () {
      final utcTime = DateTime.utc(2026, 5, 23, 14, 30, 45);
      final input = UpdatePatientInput(
        patientId: 'p1',
        fullName: 'Test',
        expectedUpdatedAt: utcTime,
      );

      expect(input.expectedUpdatedAt.isUtc, isTrue);
      expect(input.expectedUpdatedAt, utcTime);
    });

    test('expectedUpdatedAt can accept local time', () {
      final localTime = DateTime(2026, 5, 23, 14, 30, 45);
      final input = UpdatePatientInput(
        patientId: 'p1',
        fullName: 'Test',
        expectedUpdatedAt: localTime,
      );

      expect(input.expectedUpdatedAt, localTime);
    });
  });

  group('PatientSearchPage constructor', () {
    test('constructs with required fields', () {
      const page = PatientSearchPage(
        items: [],
        totalCount: 0,
        limit: 25,
        offset: 0,
      );

      expect(page.items, isEmpty);
      expect(page.totalCount, 0);
      expect(page.limit, 25);
      expect(page.offset, 0);
    });
  });
}
