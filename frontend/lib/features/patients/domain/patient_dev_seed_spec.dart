import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';

/// Which registering branch a dev seed patient should use.
enum PatientDevSeedBranchTarget {
  /// Active branch at seed time (typically the main / first branch).
  main,

  /// Second branch in the organization (created during seed if missing).
  other,
}

/// Definition of one patient row for local dev seeding.
class PatientDevSeedSpec {
  const PatientDevSeedSpec({
    required this.fullName,
    required this.phone,
    this.dateOfBirth,
    this.gender,
    this.maritalStatus,
    this.notes,
    this.branchTarget = PatientDevSeedBranchTarget.main,
    this.archiveAfterCreate = false,
  });

  final String fullName;
  final String phone;
  final DateTime? dateOfBirth;
  final PatientGender? gender;
  final PatientMaritalStatus? maritalStatus;
  final String? notes;
  final PatientDevSeedBranchTarget branchTarget;
  final bool archiveAfterCreate;

  static const devNamePrefix = '[Dev] ';
}
