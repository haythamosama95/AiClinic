import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';

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
  void goForgotPassword() => _context.go(AppRoutes.forgotPassword);
  void goStartupEntry() => _context.go(AppRoutes.startupEntry);
  void goStaffCreate() => _context.go(AppRoutes.staffCreate);
  void goStaffPasswordReset() => _context.go(AppRoutes.staffPasswordReset);

  // Patient management
  void goPatients() => _context.go(AppRoutes.patients);
  void goPatientDetail(String id) => _context.go(AppRoutes.patientDetail(id));
  void pushPatientDetail(String id) => _context.push(AppRoutes.patientDetail(id));
  void goPatientEdit(String id) => _context.go(AppRoutes.patientEdit(id));
  void pushPatientEdit(String id) => _context.push(AppRoutes.patientEdit(id));
  void goPatientRegister() => _context.push(AppRoutes.patientsNew);

  // Appointments (V1-4)
  void goAppointments() => _context.go(AppRoutes.appointments);
  void goAppointmentsBook() => _context.push(AppRoutes.appointmentsBook);
  void goAppointmentsQueue() => _context.push(AppRoutes.appointmentsQueue);
  void goAppointmentsCalendar() => _context.push(AppRoutes.appointmentsCalendar);
  void goAppointmentsSchedule(String doctorId) => _context.push(AppRoutes.appointmentsSchedule(doctorId));

  // Billing (V1-6)
  void goBillingInvoices() => _context.go(AppRoutes.billingInvoices);
  void pushBillingInvoiceDetail(String invoiceId) => _context.push(AppRoutes.billingInvoiceDetail(invoiceId));
  void pushBillingInvoiceEdit(String invoiceId) => _context.push(AppRoutes.billingInvoiceEdit(invoiceId));

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
