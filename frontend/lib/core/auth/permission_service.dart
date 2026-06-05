import 'package:ai_clinic/core/errors/exceptions.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';

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

  bool canManageBranches() => hasPermission(PermissionKeys.manageBranches);

  bool canManageStaff() => hasPermission(PermissionKeys.manageStaff);

  bool canViewPatients() => hasPermission(PermissionKeys.patientsView);

  bool canCreatePatients() => hasPermission(PermissionKeys.patientsCreate);

  bool canEditPatients() => hasPermission(PermissionKeys.patientsEdit);

  bool canDeletePatients() => hasPermission(PermissionKeys.patientsDelete);

  bool canAccessAppointments() => hasAnyPermission([
    PermissionKeys.appointmentsCreate,
    PermissionKeys.appointmentsCancel,
    PermissionKeys.appointmentsRead,
  ]);

  bool canCreateAppointments() => hasPermission(PermissionKeys.appointmentsCreate);

  bool canCancelAppointments() => hasPermission(PermissionKeys.appointmentsCancel);

  bool canCreateVisits() => hasPermission(PermissionKeys.visitsCreate);

  bool canEditVisitSoap() => hasPermission(PermissionKeys.visitsEditSoap);

  bool canUploadVisitAttachments() => hasAnyPermission([
    PermissionKeys.visitsUploadAttachment,
    PermissionKeys.visitsCreate,
    PermissionKeys.visitsEditSoap,
  ]);

  bool canViewVisitClinicalDetail() => hasAnyPermission([PermissionKeys.visitsCreate, PermissionKeys.visitsEditSoap]);

  bool canViewInvoices() => hasPermission(PermissionKeys.invoicesView);

  bool canCreateInvoices() => hasPermission(PermissionKeys.invoicesCreate);

  bool canApplyDiscount() => hasPermission(PermissionKeys.invoicesApplyDiscount);

  bool canVoidInvoice() => hasPermission(PermissionKeys.invoicesVoid);

  bool canRecordPayment() => hasPermission(PermissionKeys.paymentsRecord);

  bool canRefundPayment() => hasPermission(PermissionKeys.paymentsRefund);

  bool canManageInsurance() => hasPermission(PermissionKeys.insuranceManage);

  bool canManageBillingSettings() => hasPermission(PermissionKeys.settingsBillingManage);

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
