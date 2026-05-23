import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_row_parsing.dart';
import 'package:flutter/foundation.dart';

/// Full patient profile for detail and edit flows (V1-3).
@immutable
class PatientDetail {
  const PatientDetail({
    required this.id,
    required this.fullName,
    required this.branchId,
    required this.branchName,
    required this.createdAt,
    required this.updatedAt,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.nationalId,
    this.notes,
    this.createdByDisplay,
  });

  final String id;
  final String fullName;
  final String? phone;
  final DateTime? dateOfBirth;
  final PatientGender? gender;
  final String? nationalId;
  final String? notes;
  final String branchId;
  final String branchName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdByDisplay;

  static PatientDetail? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final fullName = row['full_name']?.toString().trim();
    final branchId = row['branch_id']?.toString();
    final branchName = row['branch_name']?.toString().trim();
    final createdAt = parsePatientDateTime(row['created_at']);
    final updatedAt = parsePatientDateTime(row['updated_at']);
    if (id == null ||
        id.isEmpty ||
        fullName == null ||
        fullName.isEmpty ||
        branchId == null ||
        branchId.isEmpty ||
        branchName == null ||
        branchName.isEmpty ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }

    return PatientDetail(
      id: id,
      fullName: fullName,
      phone: optionalPatientString(row['phone']),
      dateOfBirth: parsePatientDate(row['date_of_birth']),
      gender: PatientGender.tryParse(row['gender']?.toString()),
      nationalId: optionalPatientString(row['national_id']),
      notes: optionalPatientString(row['notes']),
      branchId: branchId,
      branchName: branchName,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdByDisplay: optionalPatientString(row['created_by_display'] ?? row['created_by_name']),
    );
  }

  PatientDetail copyWith({
    String? id,
    String? fullName,
    String? phone,
    DateTime? dateOfBirth,
    PatientGender? gender,
    String? nationalId,
    String? notes,
    String? branchId,
    String? branchName,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdByDisplay,
  }) {
    return PatientDetail(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      nationalId: nationalId ?? this.nationalId,
      notes: notes ?? this.notes,
      branchId: branchId ?? this.branchId,
      branchName: branchName ?? this.branchName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdByDisplay: createdByDisplay ?? this.createdByDisplay,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PatientDetail &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            fullName == other.fullName &&
            phone == other.phone &&
            dateOfBirth == other.dateOfBirth &&
            gender == other.gender &&
            nationalId == other.nationalId &&
            notes == other.notes &&
            branchId == other.branchId &&
            branchName == other.branchName &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt &&
            createdByDisplay == other.createdByDisplay;
  }

  @override
  int get hashCode => Object.hash(
    id,
    fullName,
    phone,
    dateOfBirth,
    gender,
    nationalId,
    notes,
    branchId,
    branchName,
    createdAt,
    updatedAt,
    createdByDisplay,
  );
}
