import 'package:ai_clinic/features/patients/domain/patient_dev_seed_data.dart';
import 'package:ai_clinic/features/patients/domain/patient_dev_seed_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientDevSeedData invariants', () {
    test('has at least 15 patients for meaningful dev testing', () {
      expect(PatientDevSeedData.patients.length, greaterThanOrEqualTo(15));
    });

    test('all patients have the [Dev] name prefix', () {
      for (final spec in PatientDevSeedData.patients) {
        expect(
          spec.fullName.startsWith(PatientDevSeedSpec.devNamePrefix),
          isTrue,
          reason: '${spec.fullName} should start with "${PatientDevSeedSpec.devNamePrefix}"',
        );
      }
    });

    test('all patients have non-empty phone numbers', () {
      for (final spec in PatientDevSeedData.patients) {
        expect(spec.phone, isNotEmpty, reason: '${spec.fullName} needs a phone');
      }
    });

    test('phone numbers are unique across all seed patients', () {
      final phones = PatientDevSeedData.patients.map((s) => s.phone).toSet();
      expect(phones.length, PatientDevSeedData.patients.length,
          reason: 'duplicate phone numbers in seed data');
    });

    test('full names are unique across all seed patients', () {
      final names = PatientDevSeedData.patients.map((s) => s.fullName).toSet();
      expect(names.length, PatientDevSeedData.patients.length,
          reason: 'duplicate full names in seed data');
    });

    test('has patients for both branch targets', () {
      final mainCount = PatientDevSeedData.patients
          .where((s) => s.branchTarget == PatientDevSeedBranchTarget.main)
          .length;
      final otherCount = PatientDevSeedData.patients
          .where((s) => s.branchTarget == PatientDevSeedBranchTarget.other)
          .length;

      expect(mainCount, greaterThan(0), reason: 'need main branch patients');
      expect(otherCount, greaterThan(0), reason: 'need other branch patients');
    });

    test('has at least one patient to archive after create', () {
      final archived = PatientDevSeedData.patients.where((s) => s.archiveAfterCreate).toList();
      expect(archived, isNotEmpty);
    });

    test('has archived patients across both branches', () {
      final archivedMain = PatientDevSeedData.patients
          .where((s) => s.archiveAfterCreate && s.branchTarget == PatientDevSeedBranchTarget.main)
          .length;
      final archivedOther = PatientDevSeedData.patients
          .where((s) => s.archiveAfterCreate && s.branchTarget == PatientDevSeedBranchTarget.other)
          .length;

      expect(archivedMain, greaterThan(0));
      expect(archivedOther, greaterThan(0));
    });

    test('has patients with all demographic combinations for coverage', () {
      final withDob = PatientDevSeedData.patients.where((s) => s.dateOfBirth != null).length;
      final withGender = PatientDevSeedData.patients.where((s) => s.gender != null).length;
      final withMaritalStatus = PatientDevSeedData.patients.where((s) => s.maritalStatus != null).length;
      final withNotes = PatientDevSeedData.patients.where((s) => s.notes != null).length;

      expect(withDob, greaterThan(0), reason: 'need patients with DOB');
      expect(withGender, greaterThan(0), reason: 'need patients with gender');
      expect(withMaritalStatus, greaterThan(0), reason: 'need patients with marital status');
      expect(withNotes, greaterThan(0), reason: 'need patients with notes');
    });

    test('has patients without optional demographics (minimal profiles)', () {
      final minimal = PatientDevSeedData.patients.where(
        (s) => s.dateOfBirth == null && s.gender == null && s.maritalStatus == null && s.notes == null,
      );
      expect(minimal, isNotEmpty, reason: 'need at least one minimal profile');
    });
  });

  group('PatientDevSeedSpec', () {
    test('devNamePrefix is non-empty and includes trailing space', () {
      expect(PatientDevSeedSpec.devNamePrefix, isNotEmpty);
      expect(PatientDevSeedSpec.devNamePrefix, endsWith(' '));
    });

    test('archiveAfterCreate defaults to false', () {
      const spec = PatientDevSeedSpec(fullName: 'Test', phone: '123');
      expect(spec.archiveAfterCreate, isFalse);
    });

    test('branchTarget defaults to main', () {
      const spec = PatientDevSeedSpec(fullName: 'Test', phone: '123');
      expect(spec.branchTarget, PatientDevSeedBranchTarget.main);
    });
  });
}
