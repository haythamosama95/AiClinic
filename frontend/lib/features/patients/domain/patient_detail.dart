import 'package:ai_clinic/core/utils/copy_with_sentinel.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
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
    this.maritalStatus,
    this.notes,
    this.createdByDisplay,
  });

  final String id;
  final String fullName;
  final String? phone;
  final DateTime? dateOfBirth;
  final PatientGender? gender;
  final PatientMaritalStatus? maritalStatus;
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
      maritalStatus: PatientMaritalStatus.tryParse(row['marital_status']?.toString()),
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
    Object? phone = copyWithSentinel,
    Object? dateOfBirth = copyWithSentinel,
    Object? gender = copyWithSentinel,
    Object? maritalStatus = copyWithSentinel,
    Object? notes = copyWithSentinel,
    String? branchId,
    String? branchName,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? createdByDisplay = copyWithSentinel,
  }) {
    return PatientDetail(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phone: identical(phone, copyWithSentinel) ? this.phone : phone as String?,
      dateOfBirth: identical(dateOfBirth, copyWithSentinel) ? this.dateOfBirth : dateOfBirth as DateTime?,
      gender: identical(gender, copyWithSentinel) ? this.gender : gender as PatientGender?,
      maritalStatus: identical(maritalStatus, copyWithSentinel) ? this.maritalStatus : maritalStatus as PatientMaritalStatus?,
      notes: identical(notes, copyWithSentinel) ? this.notes : notes as String?,
      branchId: branchId ?? this.branchId,
      branchName: branchName ?? this.branchName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdByDisplay: identical(createdByDisplay, copyWithSentinel) ? this.createdByDisplay : createdByDisplay as String?,
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
            maritalStatus == other.maritalStatus &&
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
    maritalStatus,
    notes,
    branchId,
    branchName,
    createdAt,
    updatedAt,
    createdByDisplay,
  );
}
