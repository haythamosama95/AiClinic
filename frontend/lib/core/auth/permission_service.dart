import 'package:ai_clinic/core/errors/exceptions.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';

/// Client-side permission checks against cached session grants (UX layer only).
class PermissionService {
  const PermissionService(this._context);

  final AuthSessionContext? _context;

  bool hasPermission(String key) {
    final context = _context;
    if (context == null) {
      return false;
    }

    if (!context.hasBranchAssignment) {
      return false;
    }

    return context.permissions.contains(key);
  }

  bool hasAnyPermission(Iterable<String> keys) {
    for (final key in keys) {
      if (hasPermission(key)) {
        return true;
      }
    }
    return false;
  }

  /// V1-2 branch administration (`settings.manage_branches`).
  bool canManageBranches() => hasPermission('settings.manage_branches');

  /// V1-2 staff administration (`settings.manage_staff`).
  bool canManageStaff() => hasPermission('settings.manage_staff');

  /// V1-3 patient registry (`patients.view`).
  bool canViewPatients() => hasPermission('patients.view');

  /// V1-3 patient registration (`patients.create`).
  bool canCreatePatients() => hasPermission('patients.create');

  /// V1-3 patient profile edit (`patients.edit`).
  bool canEditPatients() => hasPermission('patients.edit');

  /// V1-3 patient archive (`patients.delete`).
  bool canDeletePatients() => hasPermission('patients.delete');

  void requirePermission(String key) {
    if (!hasPermission(key)) {
      throw const PermissionDeniedException('You do not have permission to perform this action.');
    }
  }
}

/// Thrown when a gated action is attempted without the required permission.
class PermissionDeniedException extends AppException {
  const PermissionDeniedException(super.message, {super.details});
}
