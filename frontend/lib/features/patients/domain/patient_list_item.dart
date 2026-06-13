import 'package:ai_clinic/core/utils/copy_with_sentinel.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_row_parsing.dart';
import 'package:flutter/foundation.dart';

/// Patient row for list/search results (V1-3).
@immutable
class PatientListItem {
  const PatientListItem({
    required this.id,
    required this.fullName,
    required this.registeringBranchId,
    required this.registeringBranchName,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.lastVisitAt,
    this.nextAppointmentAt,
  });

  final String id;
  final String fullName;
  final String? phone;
  final DateTime? dateOfBirth;
  final PatientGender? gender;
  final DateTime? lastVisitAt;
  final DateTime? nextAppointmentAt;
  final String registeringBranchId;
  final String registeringBranchName;

  static PatientListItem? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final fullName = row['full_name']?.toString().trim();
    final branchId = row['branch_id']?.toString();
    final branchName = row['branch_name']?.toString().trim();
    if (id == null ||
        id.isEmpty ||
        fullName == null ||
        fullName.isEmpty ||
        branchId == null ||
        branchId.isEmpty ||
        branchName == null ||
        branchName.isEmpty) {
      return null;
    }

    return PatientListItem(
      id: id,
      fullName: fullName,
      phone: optionalPatientString(row['phone']),
      dateOfBirth: parsePatientDate(row['date_of_birth']),
      gender: PatientGender.tryParse(row['gender']?.toString()),
      lastVisitAt: parsePatientDate(row['last_visit_at']),
      nextAppointmentAt: parsePatientDateTime(row['next_appointment_at']),
      registeringBranchId: branchId,
      registeringBranchName: branchName,
    );
  }

  PatientListItem copyWith({
    String? id,
    String? fullName,
    Object? phone = copyWithSentinel,
    Object? dateOfBirth = copyWithSentinel,
    Object? gender = copyWithSentinel,
    Object? lastVisitAt = copyWithSentinel,
    Object? nextAppointmentAt = copyWithSentinel,
    String? registeringBranchId,
    String? registeringBranchName,
  }) {
    return PatientListItem(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phone: identical(phone, copyWithSentinel) ? this.phone : phone as String?,
      dateOfBirth: identical(dateOfBirth, copyWithSentinel) ? this.dateOfBirth : dateOfBirth as DateTime?,
      gender: identical(gender, copyWithSentinel) ? this.gender : gender as PatientGender?,
      lastVisitAt: identical(lastVisitAt, copyWithSentinel) ? this.lastVisitAt : lastVisitAt as DateTime?,
      nextAppointmentAt: identical(nextAppointmentAt, copyWithSentinel)
          ? this.nextAppointmentAt
          : nextAppointmentAt as DateTime?,
      registeringBranchId: registeringBranchId ?? this.registeringBranchId,
      registeringBranchName: registeringBranchName ?? this.registeringBranchName,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PatientListItem &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            fullName == other.fullName &&
            phone == other.phone &&
            dateOfBirth == other.dateOfBirth &&
            gender == other.gender &&
            lastVisitAt == other.lastVisitAt &&
            nextAppointmentAt == other.nextAppointmentAt &&
            registeringBranchId == other.registeringBranchId &&
            registeringBranchName == other.registeringBranchName;
  }

  @override
  int get hashCode => Object.hash(
    id,
    fullName,
    phone,
    dateOfBirth,
    gender,
    lastVisitAt,
    nextAppointmentAt,
    registeringBranchId,
    registeringBranchName,
  );
}
