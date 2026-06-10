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
  static const appointmentsRead = 'appointments.read';
  static const visitsCreate = 'visits.create';
  static const visitsEditSoap = 'visits.edit_soap';
  static const visitsUploadAttachment = 'visits.upload_attachment';
  static const analyticsView = 'analytics.view';
  static const aiAccess = 'ai.access';
  static const invoicesView = 'invoices.view';
  static const invoicesCreate = 'invoices.create';
  static const invoicesApplyDiscount = 'invoices.apply_discount';
  static const invoicesVoid = 'invoices.void';
  static const paymentsRecord = 'payments.record';
  static const paymentsRefund = 'payments.refund';
  static const insuranceManage = 'insurance.manage';
  static const settingsBillingManage = 'settings.billing.manage';
  static const shiftsManage = 'shifts.manage';
}

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
