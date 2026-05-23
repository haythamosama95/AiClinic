import 'package:ai_clinic/features/patients/domain/patient_row_parsing.dart';
import 'package:flutter/foundation.dart';

/// Possible duplicate patient surfaced before create/update (V1-3).
@immutable
class DuplicateCandidate {
  const DuplicateCandidate({
    required this.id,
    required this.fullName,
    required this.branchName,
    this.phone,
    this.dateOfBirth,
  });

  final String id;
  final String fullName;
  final String? phone;
  final DateTime? dateOfBirth;
  final String branchName;

  static DuplicateCandidate? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final fullName = row['full_name']?.toString().trim();
    final branchName = row['branch_name']?.toString().trim();
    if (id == null || id.isEmpty || fullName == null || fullName.isEmpty || branchName == null || branchName.isEmpty) {
      return null;
    }

    return DuplicateCandidate(
      id: id,
      fullName: fullName,
      phone: optionalPatientString(row['phone']),
      dateOfBirth: parsePatientDate(row['date_of_birth']),
      branchName: branchName,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DuplicateCandidate &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            fullName == other.fullName &&
            phone == other.phone &&
            dateOfBirth == other.dateOfBirth &&
            branchName == other.branchName;
  }

  @override
  int get hashCode => Object.hash(id, fullName, phone, dateOfBirth, branchName);
}
