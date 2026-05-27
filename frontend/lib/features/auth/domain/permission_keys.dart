import 'package:ai_clinic/features/auth/domain/auth_session.dart';

/// Permission key strings aligned with `roles_permissions` seed (specs/002-auth-rbac).
abstract final class PermissionKeys {
  static const manageStaff = 'settings.manage_staff';
  static const manageBranches = 'settings.manage_branches';
  static const patientsView = 'patients.view';
  static const patientsCreate = 'patients.create';
  static const patientsEdit = 'patients.edit';
  static const patientsDelete = 'patients.delete';
  static const appointmentsCreate = 'appointments.create';
  static const appointmentsCancel = 'appointments.cancel';
  static const analyticsView = 'analytics.view';
  static const aiAccess = 'ai.access';
  static const invoicesCreate = 'invoices.create';
}

/// Expected V1-1 seed grants per role (for tests and RBAC demo verification).
abstract final class RolePermissionSeed {
  static const owner = {
    PermissionKeys.manageStaff,
    PermissionKeys.manageBranches,
    PermissionKeys.patientsView,
    PermissionKeys.patientsCreate,
    PermissionKeys.patientsEdit,
    PermissionKeys.patientsDelete,
    PermissionKeys.appointmentsCreate,
    PermissionKeys.appointmentsCancel,
    PermissionKeys.analyticsView,
    PermissionKeys.aiAccess,
    PermissionKeys.invoicesCreate,
  };

  static const administrator = owner;

  static const doctor = {
    PermissionKeys.patientsView,
    PermissionKeys.patientsCreate,
    PermissionKeys.appointmentsCreate,
    PermissionKeys.appointmentsCancel,
    PermissionKeys.aiAccess,
  };

  static const receptionist = {
    PermissionKeys.patientsView,
    PermissionKeys.appointmentsCreate,
    PermissionKeys.appointmentsCancel,
    PermissionKeys.invoicesCreate,
  };

  static const labStaff = {PermissionKeys.patientsView};

  static Set<String> forRole(StaffRole role) => switch (role) {
    StaffRole.owner => owner,
    StaffRole.administrator => administrator,
    StaffRole.doctor => doctor,
    StaffRole.receptionist => receptionist,
    StaffRole.labStaff => labStaff,
  };
}
