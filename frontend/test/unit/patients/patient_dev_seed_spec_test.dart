import 'package:ai_clinic/features/patients/domain/patient_dev_seed_spec.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientDevSeedSpec.mrnForSeedOrder', () {
    test('trivial: pads single-digit order to six digits', () {
      expect(PatientDevSeedSpec.mrnForSeedOrder(1), 'MRN-000001');
    });

    test('trivial: pads double-digit order', () {
      expect(PatientDevSeedSpec.mrnForSeedOrder(10), 'MRN-000010');
    });

    test('trivial: formats large order without extra padding', () {
      expect(PatientDevSeedSpec.mrnForSeedOrder(999999), 'MRN-999999');
    });

    test('edge case: zero formats as all-zero suffix', () {
      expect(PatientDevSeedSpec.mrnForSeedOrder(0), 'MRN-000000');
    });

    test('edge case: negative index uses padLeft without validation', () {
      expect(PatientDevSeedSpec.mrnForSeedOrder(-1), 'MRN-0000-1');
    });
  });

  group('PatientDevSeedSpec', () {
    test('trivial: devNamePrefix is fixed', () {
      expect(PatientDevSeedSpec.devNamePrefix, '[Dev] ');
    });

    test('trivial: required fields are assigned', () {
      const spec = PatientDevSeedSpec(
        fullName: 'Dev Patient',
        phone: '201000000001',
      );

      expect(spec.fullName, 'Dev Patient');
      expect(spec.phone, '201000000001');
    });

    test('trivial: optional fields default to null or enum defaults', () {
      const spec = PatientDevSeedSpec(
        fullName: 'Dev Patient',
        phone: '201000000001',
      );

      expect(spec.dateOfBirth, isNull);
      expect(spec.gender, isNull);
      expect(spec.maritalStatus, isNull);
      expect(spec.notes, isNull);
      expect(spec.branchTarget, PatientDevSeedBranchTarget.main);
      expect(spec.archiveAfterCreate, isFalse);
    });

    test('advanced: optional fields can be set explicitly', () {
      final dob = DateTime(1990, 5, 15);
      final spec = PatientDevSeedSpec(
        fullName: 'Dev Patient',
        phone: '201000000001',
        dateOfBirth: dob,
        gender: PatientGender.female,
        maritalStatus: PatientMaritalStatus.married,
        notes: 'Seed notes',
        branchTarget: PatientDevSeedBranchTarget.other,
        archiveAfterCreate: true,
      );

      expect(spec.dateOfBirth, dob);
      expect(spec.gender, PatientGender.female);
      expect(spec.maritalStatus, PatientMaritalStatus.married);
      expect(spec.notes, 'Seed notes');
      expect(spec.branchTarget, PatientDevSeedBranchTarget.other);
      expect(spec.archiveAfterCreate, isTrue);
    });
  });
}
