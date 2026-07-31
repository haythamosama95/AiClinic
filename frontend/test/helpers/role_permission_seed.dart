// Test-only V1-1 seed grants per role; mirrors backend `roles_permissions` seed.
// ignore_for_file: depend_on_referenced_packages

import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';

/// Expected V1-1 seed grants per role (for tests and RBAC demo verification).
abstract final class RolePermissionSeed {
  static const administrator = {
    PermissionKeys.manageStaff,
    PermissionKeys.manageBranches,
    PermissionKeys.patientsView,
    PermissionKeys.patientsCreate,
    PermissionKeys.patientsEdit,
    PermissionKeys.patientsDelete,
    PermissionKeys.appointmentsCreate,
    PermissionKeys.appointmentsCancel,
    PermissionKeys.appointmentsRead,
    PermissionKeys.visitsCreate,
    PermissionKeys.visitsEditSoap,
    PermissionKeys.visitsUploadAttachment,
    PermissionKeys.analyticsView,
    PermissionKeys.aiAccess,
    PermissionKeys.invoicesView,
    PermissionKeys.invoicesCreate,
    PermissionKeys.invoicesApplyDiscount,
    PermissionKeys.invoicesVoid,
    PermissionKeys.paymentsRecord,
    PermissionKeys.paymentsRefund,
    PermissionKeys.insuranceManage,
    PermissionKeys.settingsBillingManage,
    PermissionKeys.servicesView,
    PermissionKeys.servicesManage,
  };

  static const doctor = {
    PermissionKeys.patientsView,
    PermissionKeys.patientsCreate,
    PermissionKeys.appointmentsCreate,
    PermissionKeys.appointmentsCancel,
    PermissionKeys.appointmentsRead,
    PermissionKeys.visitsCreate,
    PermissionKeys.visitsEditSoap,
    PermissionKeys.visitsUploadAttachment,
    PermissionKeys.aiAccess,
  };

  static const receptionist = {
    PermissionKeys.patientsView,
    PermissionKeys.appointmentsCreate,
    PermissionKeys.appointmentsCancel,
    PermissionKeys.appointmentsRead,
    PermissionKeys.invoicesView,
    PermissionKeys.invoicesCreate,
    PermissionKeys.paymentsRecord,
  };

  static const labStaff = {
    PermissionKeys.patientsView,
    PermissionKeys.appointmentsRead,
    PermissionKeys.visitsUploadAttachment,
  };

  static Set<String> forRole(StaffRole role) => switch (role) {
    StaffRole.administrator => administrator,
    StaffRole.doctor => doctor,
    StaffRole.receptionist => receptionist,
    StaffRole.labStaff => labStaff,
  };
}
