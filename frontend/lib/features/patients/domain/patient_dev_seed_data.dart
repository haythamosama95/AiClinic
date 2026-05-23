import 'package:ai_clinic/features/patients/domain/patient_dev_seed_spec.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';

/// ~20 dev patients covering branch scope, demographics, search, and archive cases.
abstract final class PatientDevSeedData {
  static final List<PatientDevSeedSpec> patients = [
    // —— Active branch (main) ——
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}Ahmed Hassan',
      phone: '2017000001',
      dateOfBirth: DateTime(1990, 5, 15),
      gender: PatientGender.male,
      maritalStatus: PatientMaritalStatus.married,
      notes: 'Full profile — use for name/phone search and detail view.',
    ),
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}Fatima Ali',
      phone: '2017000002',
      dateOfBirth: DateTime(1995, 8, 2),
      gender: PatientGender.female,
      maritalStatus: PatientMaritalStatus.single,
    ),
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}Omar Khalil',
      phone: '2017000003',
      dateOfBirth: DateTime(1985, 3, 20),
      gender: PatientGender.male,
      maritalStatus: PatientMaritalStatus.divorced,
    ),
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}Layla Mansour',
      phone: '2017000004',
      gender: PatientGender.female,
      maritalStatus: PatientMaritalStatus.widowed,
    ),
    PatientDevSeedSpec(fullName: '${PatientDevSeedSpec.devNamePrefix}Hassan Ibrahim', phone: '2017000005'),
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}Nadia Said',
      phone: '2017000006',
      notes: 'Long notes field — reception follow-up scheduled.',
    ),
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}Michael Smith',
      phone: '2017000007',
      dateOfBirth: DateTime(1988, 11, 30),
      gender: PatientGender.male,
    ),
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}Sara Mohamed',
      phone: '20105551234',
      dateOfBirth: DateTime(1992, 1, 10),
      gender: PatientGender.female,
      notes: 'Phone prefix search: try 2010 or 20105.',
    ),
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}Ahmed Karim',
      phone: '2017000009',
      dateOfBirth: DateTime(1990, 5, 15),
      gender: PatientGender.male,
      notes: 'Similar name/DOB to Ahmed Hassan — duplicate check on manual register.',
    ),
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}100% Promo',
      phone: '2017000010',
      notes: 'Wildcard-style name for search edge cases.',
    ),
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}Young Child',
      phone: '2017000011',
      dateOfBirth: DateTime(2020, 1, 1),
      gender: PatientGender.male,
    ),
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}Elder Guest',
      phone: '2017000012',
      dateOfBirth: DateTime(1940, 6, 15),
      gender: PatientGender.female,
      maritalStatus: PatientMaritalStatus.widowed,
    ),
    // —— Other branch ——
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}Branch Two Patient',
      phone: '2017000013',
      branchTarget: PatientDevSeedBranchTarget.other,
      notes: 'Registered at second branch — hidden in “this branch only” scope.',
    ),
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}South Patient One',
      phone: '2017000014',
      branchTarget: PatientDevSeedBranchTarget.other,
      gender: PatientGender.female,
    ),
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}South Patient Two',
      phone: '2017000015',
      branchTarget: PatientDevSeedBranchTarget.other,
      gender: PatientGender.male,
      maritalStatus: PatientMaritalStatus.married,
    ),
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}Remote Visit Prep',
      phone: '2017000016',
      branchTarget: PatientDevSeedBranchTarget.other,
      dateOfBirth: DateTime(1975, 7, 4),
    ),
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}Cross Scope Test',
      phone: '2017000017',
      branchTarget: PatientDevSeedBranchTarget.other,
    ),
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}Far Branch Case',
      phone: '2017000018',
      branchTarget: PatientDevSeedBranchTarget.other,
      notes: 'Switch to “All branches” on the list to find this patient.',
    ),
    // —— Archived (excluded from normal lists) ——
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}Archived Local',
      phone: '2017000019',
      archiveAfterCreate: true,
      notes: 'Archived at main branch — should not appear in list/search.',
    ),
    PatientDevSeedSpec(
      fullName: '${PatientDevSeedSpec.devNamePrefix}Archived Remote',
      phone: '2017000020',
      branchTarget: PatientDevSeedBranchTarget.other,
      archiveAfterCreate: true,
    ),
  ];
}
