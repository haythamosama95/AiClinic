import 'package:ai_clinic/features/auth/domain/auth_session.dart';

/// Client-side guards for staff provisioning (FR-022b, FR-022c). Server RPCs remain authoritative.
abstract final class ProvisioningRules {
  /// Whether the signed-in staff member may open the create-staff flow.
  static bool canProvisionStaff(StaffProfile caller) {
    return caller.role == StaffRole.owner || caller.role == StaffRole.administrator || caller.isBootstrapAdmin;
  }

  /// Whether the signed-in staff member may reset another staff member's password (FR-024).
  static bool canResetStaffPassword(StaffProfile caller) {
    return caller.role == StaffRole.owner || caller.role == StaffRole.administrator;
  }

  /// Roles offered in the create-staff form for the current caller.
  ///
  /// [ownerAlreadyExists] should be `true` once at least one owner account exists in the clinic.
  static List<StaffRole> selectableRoles(StaffProfile caller, {required bool ownerAlreadyExists}) {
    const operational = [StaffRole.administrator, StaffRole.doctor, StaffRole.receptionist, StaffRole.labStaff];

    if (!canProvisionStaff(caller)) {
      return const [];
    }

    if (mayAssignOwnerRole(caller, ownerAlreadyExists: ownerAlreadyExists)) {
      return [StaffRole.owner, ...operational];
    }

    return operational;
  }

  /// FR-022c: first owner only by bootstrap admin; additional owners only by existing owners.
  static bool mayAssignOwnerRole(StaffProfile caller, {required bool ownerAlreadyExists}) {
    if (!ownerAlreadyExists) {
      return caller.isBootstrapAdmin;
    }
    return caller.role == StaffRole.owner;
  }

  /// Validates a role choice before calling the RPC (mirrors server rules).
  static String? validateRoleChoice(StaffProfile caller, StaffRole role, {required bool ownerAlreadyExists}) {
    if (!canProvisionStaff(caller)) {
      return 'Only clinic owners and administrators can create staff accounts.';
    }

    if (role == StaffRole.owner && !mayAssignOwnerRole(caller, ownerAlreadyExists: ownerAlreadyExists)) {
      if (!ownerAlreadyExists) {
        return 'Only the bootstrap administrator can create the first owner account.';
      }
      return 'Only existing owners can create additional owner accounts.';
    }

    return null;
  }

  /// Infers whether an owner likely already exists from the caller profile alone.
  static bool inferOwnerAlreadyExists(StaffProfile caller) {
    if (caller.role == StaffRole.owner) {
      return true;
    }
    if (caller.role == StaffRole.administrator && !caller.isBootstrapAdmin) {
      return true;
    }
    return false;
  }
}
