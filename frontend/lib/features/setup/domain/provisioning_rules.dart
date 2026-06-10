import 'package:ai_clinic/features/auth/domain/auth_session.dart';

/// Client-side guards for staff provisioning (FR-022b). Server RPCs remain authoritative.
abstract final class ProvisioningRules {
  /// Whether the signed-in staff member may open the create-staff flow.
  static bool canProvisionStaff(StaffProfile caller) {
    return caller.role == StaffRole.administrator || caller.isBootstrapAdmin;
  }

  /// Whether the signed-in staff member may reset another staff member's password (FR-024).
  static bool canResetStaffPassword(StaffProfile caller) {
    return caller.role == StaffRole.administrator;
  }

  /// Roles offered in the create-staff form for the current caller.
  static List<StaffRole> selectableRoles(StaffProfile caller) {
    const operational = [StaffRole.administrator, StaffRole.doctor, StaffRole.receptionist, StaffRole.labStaff];

    if (!canProvisionStaff(caller)) {
      return const [];
    }

    return operational;
  }

  /// Validates a role choice before calling the RPC (mirrors server rules).
  static String? validateRoleChoice(StaffProfile caller, StaffRole role) {
    if (!canProvisionStaff(caller)) {
      return 'Only clinic administrators can create staff accounts.';
    }

    if (!selectableRoles(caller).contains(role)) {
      return 'You do not have permission to assign this role.';
    }

    return null;
  }
}
