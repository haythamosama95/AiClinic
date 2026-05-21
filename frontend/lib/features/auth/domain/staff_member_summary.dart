import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter/foundation.dart';

/// Staff row shown in administrator password-reset picker (RLS-scoped list).
@immutable
class StaffMemberSummary {
  const StaffMemberSummary({required this.id, required this.fullName, required this.role});

  final String id;
  final String fullName;
  final StaffRole role;

  static StaffMemberSummary? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final fullName = row['full_name']?.toString().trim();
    final role = StaffRole.tryParse(row['role']?.toString());
    if (id == null || id.isEmpty || fullName == null || fullName.isEmpty || role == null) {
      return null;
    }

    return StaffMemberSummary(id: id, fullName: fullName, role: role);
  }

  String get roleLabel => role.wireValue;
}
