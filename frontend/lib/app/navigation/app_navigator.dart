import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_entry.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_route_extra.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_provider.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_resolver.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/presentation/navigation/appointment_detail_route_extra.dart';
import 'package:ai_clinic/features/billing/presentation/navigation/invoice_detail_route_extra.dart';
import 'package:ai_clinic/features/billing/presentation/navigation/visit_billing_route_extra.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/navigation/patient_detail_route_extra.dart';
import 'package:ai_clinic/features/visits/presentation/navigation/visit_route_extra.dart';

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
  void goHome() {
    _context.go(AppRoutes.home);
    _syncHubTrail(AppRoutes.home);
  }

  void goLogin() => _context.go(AppRoutes.login);
  void goBootstrap() => _context.go(AppRoutes.bootstrap);
  void goForgotPassword() => _context.go('${AppRoutes.login}?forgot=1');
  void goStartupEntry() => _context.go(AppRoutes.startupEntry);
  void goStaffCreate() => _context.go(AppRoutes.staffCreate);
  void goStaffPasswordReset() => _context.go(AppRoutes.staffPasswordReset);
  void goFoundationDemo() => _context.go(AppRoutes.foundationDemo);
  void goDesignSystem() => _context.go(AppRoutes.foundationDemo);

  // Patient management
  void goPatients() {
    _context.go(AppRoutes.patients);
    _syncHubTrail(AppRoutes.patients);
  }

  void goPatientDetail(String id) {
    _navigateGo(
      AppRoutes.patientDetail(id),
      extra: const PatientDetailRouteExtra(),
      trailOverride: BreadcrumbTrailResolver.canonicalFor(AppRoutes.patientDetail(id)),
    );
  }

  void pushPatientDetail(String id, {PatientListItem? preview, Rect? sourceRect, BreadcrumbTrail? trail}) =>
      _navigatePush(
        AppRoutes.patientDetail(id),
        extra: PatientDetailRouteExtra(preview: preview, sourceRect: sourceRect),
        appendEntry: BreadcrumbEntries.patient(id, name: preview?.fullName ?? '…'),
        trailOverride: trail,
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
  void goAppointments() => goAppointmentsCalendar();

  void goAppointmentsBook() => _context.push(AppRoutes.appointmentsBook);
  void goAppointmentsQueue() {
    _context.go(AppRoutes.appointmentsQueue);
    _syncHubTrail(AppRoutes.appointmentsQueue);
  }

  void goAppointmentsCalendar() {
    _context.go(AppRoutes.appointmentsCalendar);
    _syncHubTrail(AppRoutes.appointmentsCalendar);
  }

  void pushAppointmentDetail(String appointmentId, {AppointmentListItem? preview, BreadcrumbTrail? trail}) =>
      _navigatePush(
        AppRoutes.appointmentDetail(appointmentId),
        extra: AppointmentDetailRouteExtra(preview: preview),
        appendEntry: BreadcrumbEntries.appointment(
          appointmentId,
          label: preview != null ? BreadcrumbEntries.appointmentLabelFromPreview(preview) : '…',
        ),
        trailOverride: trail,
      );

  void goAppointmentsSchedule(String doctorId) => _context.push(AppRoutes.appointmentsSchedule(doctorId));

  // Billing (V1-6)
  void goBilling() => goBillingInvoices();

  void goBillingInvoices() {
    _context.go(AppRoutes.billingInvoices);
    _syncHubTrail(AppRoutes.billingInvoices);
  }

  void pushBillingInvoiceDetail(String invoiceId, {String? invoiceNumber, BreadcrumbTrail? trail}) {
    final composedTrail =
        trail ??
        BreadcrumbTrailResolver.composeInvoiceDetailPushTrail(
          parent: BreadcrumbTrailResolver.inheritFrom(_context),
          invoiceId: invoiceId,
          invoiceNumber: invoiceNumber,
        );
    _navigatePush(
      AppRoutes.billingInvoiceDetail(invoiceId),
      extra: const InvoiceDetailRouteExtra(),
      trailOverride: composedTrail,
    );
  }

  void pushBillingInvoiceReview(String invoiceId) => _context.push(AppRoutes.billingInvoiceReview(invoiceId));
  void pushBillingInvoiceEdit(String invoiceId) => _context.push(AppRoutes.billingInvoiceEdit(invoiceId));

  void pushVisitBilling(String visitId, {BreadcrumbTrail? trail}) => _navigatePush(
    AppRoutes.billingVisit(visitId),
    extra: const VisitBillingRouteExtra(),
    appendEntry: BreadcrumbEntries.visitBilling(visitId),
    trailOverride: trail,
  );

  // Visits (V1-5)
  void goVisitDocument(String visitId, {BreadcrumbTrail? trail}) => _navigateGo(
    AppRoutes.visitDocument(visitId),
    extra: const VisitRouteExtra(),
    appendEntry: trail == null ? BreadcrumbEntries.visitDocument(visitId) : null,
    trailOverride: trail,
  );

  void pushVisitDocument(String visitId, {BreadcrumbTrail? trail}) => _navigatePush(
    AppRoutes.visitDocument(visitId),
    extra: const VisitRouteExtra(),
    appendEntry: BreadcrumbEntries.visitDocument(visitId),
    trailOverride: trail,
  );

  void goVisitDetail(String visitId, {BreadcrumbTrail? trail}) => _navigateGo(
    AppRoutes.visitDetail(visitId),
    extra: const VisitRouteExtra(),
    appendEntry: trail == null ? BreadcrumbEntries.visitDetail(visitId) : null,
    trailOverride: trail,
  );

  void pushVisitDetail(String visitId, {BreadcrumbTrail? trail}) => _navigatePush(
    AppRoutes.visitDetail(visitId),
    extra: const VisitRouteExtra(),
    appendEntry: BreadcrumbEntries.visitDetail(visitId),
    trailOverride: trail,
  );

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
      goHome();
    }
  }

  void _navigatePush(String location, {Object? extra, BreadcrumbEntry? appendEntry, BreadcrumbTrail? trailOverride}) {
    final trail = _composeTrail(appendEntry: appendEntry, trailOverride: trailOverride);
    final syncedExtra = _mergeBreadcrumbExtra(extra, trail);
    _context.push(location, extra: syncedExtra);
    _syncBreadcrumbNotifier(trail, syncedLocation: location);
  }

  void _navigateGo(String location, {Object? extra, BreadcrumbEntry? appendEntry, BreadcrumbTrail? trailOverride}) {
    final trail = _composeTrail(appendEntry: appendEntry, trailOverride: trailOverride);
    final syncedExtra = _mergeBreadcrumbExtra(extra, trail);
    _context.go(location, extra: syncedExtra);
    _syncBreadcrumbNotifier(trail, syncedLocation: location);
  }

  BreadcrumbTrail _composeTrail({BreadcrumbEntry? appendEntry, BreadcrumbTrail? trailOverride}) {
    if (trailOverride != null) {
      return trailOverride;
    }
    final parent = BreadcrumbTrailResolver.inheritFrom(_context);
    if (appendEntry != null) {
      return parent.append(appendEntry);
    }
    return parent;
  }

  void _syncHubTrail(String location) {
    _syncBreadcrumbNotifier(BreadcrumbTrailResolver.canonicalFor(location), syncedLocation: location);
  }

  void _syncBreadcrumbNotifier(BreadcrumbTrail trail, {required String syncedLocation}) {
    ProviderScope.containerOf(
      _context,
      listen: false,
    ).read(breadcrumbTrailProvider.notifier).setTrail(trail, syncedLocation: syncedLocation);
  }

  void goVisitDocumentFromDetail(String visitId) {
    goVisitDocument(
      visitId,
      trail: BreadcrumbTrailResolver.composeVisitDocumentFromDetail(
        parent: BreadcrumbTrailResolver.inheritFrom(_context),
        visitId: visitId,
      ),
    );
  }

  Object? _mergeBreadcrumbExtra(Object? extra, BreadcrumbTrail trail) {
    if (extra is PatientDetailRouteExtra) {
      return PatientDetailRouteExtra(preview: extra.preview, sourceRect: extra.sourceRect, breadcrumbTrail: trail);
    }
    if (extra is AppointmentDetailRouteExtra) {
      return AppointmentDetailRouteExtra(preview: extra.preview, breadcrumbTrail: trail);
    }
    if (extra is VisitRouteExtra) {
      return VisitRouteExtra(breadcrumbTrail: trail);
    }
    if (extra is InvoiceDetailRouteExtra) {
      return InvoiceDetailRouteExtra(breadcrumbTrail: trail);
    }
    if (extra is VisitBillingRouteExtra) {
      return VisitBillingRouteExtra(breadcrumbTrail: trail);
    }
    if (extra is BreadcrumbRouteExtra) {
      return extra;
    }
    return extra;
  }
}
