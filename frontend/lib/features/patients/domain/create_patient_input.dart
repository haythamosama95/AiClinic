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
    this.mrn,
    this.acknowledgeDuplicate = false,
  });

  final String activeBranchId;
  final String fullName;
  final String phone;
  final DateTime? dateOfBirth;
  final PatientGender? gender;
  final PatientMaritalStatus? maritalStatus;
  final String? notes;

  /// Optional explicit MRN (validated server-side). Used by dev seed flows.
  final String? mrn;
  final bool acknowledgeDuplicate;

  CreatePatientInput copyWith({
    String? activeBranchId,
    String? fullName,
    String? phone,
    DateTime? dateOfBirth,
    PatientGender? gender,
    PatientMaritalStatus? maritalStatus,
    String? notes,
    String? mrn,
    bool? acknowledgeDuplicate,
  }) {
    return CreatePatientInput(
      activeBranchId: activeBranchId ?? this.activeBranchId,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      notes: notes ?? this.notes,
      mrn: mrn ?? this.mrn,
      acknowledgeDuplicate: acknowledgeDuplicate ?? this.acknowledgeDuplicate,
    );
  }
}
