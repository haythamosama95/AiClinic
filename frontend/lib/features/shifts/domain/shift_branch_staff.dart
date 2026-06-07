import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter/foundation.dart';

/// Active staff member eligible for shift assignment at a branch (V1-7).
@immutable
class ShiftBranchStaffMember {
  const ShiftBranchStaffMember({required this.id, required this.fullName, required this.role});

  final String id;
  final String fullName;
  final StaffRole role;

  static ShiftBranchStaffMember? fromAssignmentRow(Map<String, dynamic> row) {
    final staffRaw = row['staff_members'];
    if (staffRaw is! Map) {
      return null;
    }
    final staff = Map<String, dynamic>.from(staffRaw);
    if (staff['is_active'] != true) {
      return null;
    }
    final id = staff['id']?.toString();
    final fullName = staff['full_name']?.toString().trim();
    final role = StaffRole.tryParse(staff['role']?.toString());
    if (id == null || id.isEmpty || fullName == null || fullName.isEmpty || role == null) {
      return null;
    }
    return ShiftBranchStaffMember(id: id, fullName: fullName, role: role);
  }
}
