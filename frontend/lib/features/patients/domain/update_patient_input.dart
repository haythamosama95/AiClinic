import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';

/// Input for patient update.
class UpdatePatientInput {
  const UpdatePatientInput({
    required this.patientId,
    required this.fullName,
    required this.expectedUpdatedAt,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.maritalStatus,
    this.notes,
    this.acknowledgeDuplicate = false,
  });

  final String patientId;
  final String fullName;
  final DateTime expectedUpdatedAt;
  final String? phone;
  final DateTime? dateOfBirth;
  final PatientGender? gender;
  final PatientMaritalStatus? maritalStatus;
  final String? notes;
  final bool acknowledgeDuplicate;
}
