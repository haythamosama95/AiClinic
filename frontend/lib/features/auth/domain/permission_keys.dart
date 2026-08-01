/// Permission key strings aligned with `roles_permissions` seed (docs/specs/002-auth-rbac).
///
/// Test-only role grant fixtures live in `test/helpers/role_permission_seed.dart`
/// (`RolePermissionSeed`); runtime checks read from `AuthSessionContext.permissions`.
abstract final class PermissionKeys {
  static const manageStaff = 'settings.manage_staff';
  static const manageBranches = 'settings.manage_branches';
  static const patientsView = 'patients.view';
  static const patientsCreate = 'patients.create';
  static const patientsEdit = 'patients.edit';
  static const patientsDelete = 'patients.delete';
  static const patientsReassignMrn = 'patients.reassign_mrn';
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
  static const servicesView = 'services.view';
  static const servicesManage = 'services.manage';
}
