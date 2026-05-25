import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';

/// Input for patient creation.
class CreatePatientInput {
  const CreatePatientInput({
    required this.activeBranchId,
    required this.fullName,
    required this.phone,
    this.dateOfBirth,
    this.gender,
    this.maritalStatus,
    this.notes,
    this.acknowledgeDuplicate = false,
  });

  final String activeBranchId;
  final String fullName;
  final String phone;
  final DateTime? dateOfBirth;
  final PatientGender? gender;
  final PatientMaritalStatus? maritalStatus;
  final String? notes;
  final bool acknowledgeDuplicate;
}
