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
  });

  final String id;
  final String fullName;
  final String? phone;
  final DateTime? dateOfBirth;
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
      registeringBranchId: branchId,
      registeringBranchName: branchName,
    );
  }

  PatientListItem copyWith({
    String? id,
    String? fullName,
    String? phone,
    DateTime? dateOfBirth,
    String? registeringBranchId,
    String? registeringBranchName,
  }) {
    return PatientListItem(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
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
            registeringBranchId == other.registeringBranchId &&
            registeringBranchName == other.registeringBranchName;
  }

  @override
  int get hashCode => Object.hash(id, fullName, phone, dateOfBirth, registeringBranchId, registeringBranchName);
}
