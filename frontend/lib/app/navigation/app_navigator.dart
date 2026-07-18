import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/navigation/patient_detail_route_extra.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/presentation/navigation/appointment_detail_route_extra.dart';

/// Centralized navigation service to avoid scattered `context.go()`/`context.push()` calls.
///
/// Usage: `context.nav.goPatientDetail(patientId)`
extension AppNavigatorExt on BuildContext {
  AppNavigator get nav => AppNavigator(this);
}

class AppNavigator {
  const AppNavigator(this._context);
  final BuildContext _context;

  // Auth / startup
  void goHome() => _context.go(AppRoutes.home);
  void goLogin() => _context.go(AppRoutes.login);
  void goBootstrap() => _context.go(AppRoutes.bootstrap);
  void goForgotPassword() => _context.go('${AppRoutes.login}?forgot=1');
  void goStartupEntry() => _context.go(AppRoutes.startupEntry);
  void goStaffCreate() => _context.go(AppRoutes.staffCreate);
  void goStaffPasswordReset() => _context.go(AppRoutes.staffPasswordReset);
  void goFoundationDemo() => _context.go(AppRoutes.foundationDemo);

  void goDesignSystem() => _context.go(AppRoutes.foundationDemo);

  // Patient management
  void goPatients() => _context.go(AppRoutes.patients);
  void goPatientDetail(String id) => _context.go(AppRoutes.patientDetail(id));
  void pushPatientDetail(String id, {PatientListItem? preview, Rect? sourceRect}) => _context.push(
    AppRoutes.patientDetail(id),
    extra: PatientDetailRouteExtra(preview: preview, sourceRect: sourceRect),
  );
  void goPatientEdit(String id) => _context.go(AppRoutes.patientEdit(id));
  void pushPatientEdit(String id) => _context.push(AppRoutes.patientEdit(id));
  void goPatientRegister() => _context.push(AppRoutes.patientsNew);

  /// Navigates to patient registration; returns when the route is popped.
  Future<String?> showPatientRegister() async {
    await _context.push<String?>(AppRoutes.patientsNew);
    return null;
  }

  // Appointments (V1-4)
  void goAppointments() => _context.go(AppRoutes.appointments);
  void goAppointmentsBook() => _context.push(AppRoutes.appointmentsBook);
  void goAppointmentsQueue() => _context.push(AppRoutes.appointmentsQueue);
  void goAppointmentsCalendar() => _context.go(AppRoutes.appointmentsCalendar);
  void pushAppointmentDetail(String appointmentId, {AppointmentListItem? preview}) =>
      _context.push(AppRoutes.appointmentDetail(appointmentId), extra: AppointmentDetailRouteExtra(preview: preview));
  void goAppointmentsSchedule(String doctorId) => _context.push(AppRoutes.appointmentsSchedule(doctorId));

  // Billing (V1-6)
  void goBilling() => _context.go(AppRoutes.billing);
  void goBillingInvoices() => _context.go(AppRoutes.billingInvoices);
  void pushBillingInvoiceDetail(String invoiceId) => _context.push(AppRoutes.billingInvoiceDetail(invoiceId));
  void pushBillingInvoiceReview(String invoiceId) => _context.push(AppRoutes.billingInvoiceReview(invoiceId));
  void pushBillingInvoiceEdit(String invoiceId) => _context.push(AppRoutes.billingInvoiceEdit(invoiceId));
  void pushVisitBilling(String visitId) => _context.push(AppRoutes.billingVisit(visitId));

  // Visits (V1-5)
  void goVisitDocument(String visitId) => _context.go(AppRoutes.visitDocument(visitId));
  void pushVisitDocument(String visitId) => _context.push(AppRoutes.visitDocument(visitId));
  void goVisitDetail(String visitId) => _context.go(AppRoutes.visitDetail(visitId));
  void pushVisitDetail(String visitId) => _context.push(AppRoutes.visitDetail(visitId));

  // Settings
  void goSettings() => _context.go(AppRoutes.settings);
  void goSettingsOrganization() => _context.go(AppRoutes.settingsOrganization);
  void goSettingsBranches() => _context.go(AppRoutes.settingsBranches);
  void goSettingsBranchesNew() => _context.go(AppRoutes.settingsBranchesNew);
  void goSettingsBranchEdit(String id) => _context.go(AppRoutes.settingsBranchEdit(id));
  void goSettingsStaff() => _context.go(AppRoutes.settingsStaff);
  void goSettingsStaffNew() => _context.go(AppRoutes.settingsStaffNew);
  void goSettingsStaffDetail(String id) => _context.go(AppRoutes.settingsStaffDetail(id));
  void goSettingsStaffResetPassword(String id) => _context.go(AppRoutes.settingsStaffResetPassword(id));
  void goSettingsPermissions() => _context.go(AppRoutes.settingsPermissions);
  void goSettingsIdleTimeout() => _context.go(AppRoutes.settingsIdleTimeout);

  // Utility
  void pop() => _context.pop();
  bool canPop() => _context.canPop();
  void popOrHome() {
    if (_context.canPop()) {
      _context.pop();
    } else {
      _context.go(AppRoutes.home);
    }
  }
}
