import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Route guard rules for auth session states (see `contracts/auth-session.md`).
abstract final class AuthRouteGuard {
  /// Clinic setup destination while bootstrap is incomplete (shell stays on home; setup runs in a dialog).
  static const String clinicSetupRoute = AppRoutes.home;

  /// Routes reachable without an authenticated session.
  static bool isPublicUnauthenticatedRoute(String location) {
    return location == AppRoutes.startupEntry ||
        location == AppRoutes.startupCheck ||
        location == AppRoutes.setupGuidance ||
        location == AppRoutes.protectedBlocked ||
        location == AppRoutes.login ||
        location == AppRoutes.forgotPassword;
  }

  /// Routes that require a signed-in staff session.
  static bool requiresAuthentication(String location) {
    return location == AppRoutes.home ||
        location == AppRoutes.bootstrap ||
        location == AppRoutes.foundationDemo ||
        isSettingsRoute(location) ||
        isClinicManagementRoute(location) ||
        isPatientRoute(location) ||
        isAppointmentRoute(location) ||
        isVisitRoute(location) ||
        isBillingRoute(location) ||
        isShiftRoute(location) ||
        isStaffProvisioningRoute(location) ||
        location.startsWith('${AppRoutes.protectedPrefix}/');
  }

  /// V1-3 operational patient routes under `/patients`.
  static bool isPatientRoute(String location) {
    if (AppRoutes.patientStaticPaths.contains(location)) {
      return true;
    }
    if (!location.startsWith('${AppRoutes.patients}/')) {
      return false;
    }
    return location != AppRoutes.patients;
  }

  static bool canAccessPatientList(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    return PermissionService(auth.context).canViewPatients();
  }

  static bool canAccessPatientRegistration(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    return PermissionService(auth.context).canCreatePatients();
  }

  static bool canAccessPatientDetail(AuthSessionState auth) {
    return canAccessPatientList(auth);
  }

  static bool canAccessPatientEdit(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    return PermissionService(auth.context).canEditPatients();
  }

  static bool canAccessPatientDelete(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    return PermissionService(auth.context).canDeletePatients();
  }

  /// V1-4 appointment routes under `/appointments`.
  static bool isAppointmentRoute(String location) {
    return location == AppRoutes.appointments || location.startsWith('${AppRoutes.appointments}/');
  }

  static bool canAccessAppointmentHub(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    return PermissionService(auth.context).canAccessAppointments();
  }

  static bool canAccessAppointmentBooking(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    return PermissionService(auth.context).canCreateAppointments();
  }

  static bool canAccessAppointmentCancelActions(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    return PermissionService(auth.context).canCancelAppointments();
  }

  /// V1-5 visit routes under `/visits`.
  static bool isVisitRoute(String location) {
    return location.startsWith('${AppRoutes.visits}/');
  }

  static bool canAccessVisitDocumentation(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    final permissions = PermissionService(auth.context);
    return permissions.canCreateVisits() || permissions.canEditVisitSoap();
  }

  static bool canAccessVisitDetail(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    final permissions = PermissionService(auth.context);
    return permissions.canViewVisitClinicalDetail() || permissions.canUploadVisitAttachments();
  }

  /// Returns redirect when [location] is a visit route the session cannot access.
  static String? visitRouteRedirect({required String location, required AuthSessionState auth}) {
    if (!isVisitRoute(location)) {
      return null;
    }

    if (!auth.isAuthenticated) {
      return AppRoutes.login;
    }

    if ((auth.context?.needsClinicSetup ?? true)) {
      return clinicSetupRoute;
    }

    final allowed = location.endsWith('/${AppRoutes.visitDocumentSegment}')
        ? canAccessVisitDocumentation(auth)
        : location.endsWith('/${AppRoutes.visitDetailSegment}')
        ? canAccessVisitDetail(auth)
        : false;

    return allowed ? null : AppRoutes.home;
  }

  /// V1-6 billing routes under `/billing` and `/settings/billing`.
  static bool isBillingRoute(String location) {
    if (AppRoutes.billingStaticPaths.contains(location)) {
      return true;
    }
    if (location.startsWith('${AppRoutes.billingInvoices}/')) {
      return true;
    }
    return false;
  }

  static bool canAccessInvoiceList(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    return PermissionService(auth.context).canViewInvoices();
  }

  static bool canAccessInvoiceDetail(AuthSessionState auth) {
    return canAccessInvoiceList(auth);
  }

  static bool canAccessInvoiceEdit(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    return PermissionService(auth.context).canCreateInvoices();
  }

  static bool canAccessInsuranceProviders(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    return PermissionService(auth.context).canManageInsurance();
  }

  static bool canAccessBillingSettings(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    final permissions = PermissionService(auth.context);
    return permissions.canManageBillingSettings();
  }

  /// V1-7 shift routes under `/shifts`.
  static bool isShiftRoute(String location) {
    if (AppRoutes.shiftStaticPaths.contains(location)) {
      return true;
    }
    return location.startsWith('${AppRoutes.shifts}/');
  }

  static bool canAccessShiftCalendar(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    return PermissionService(auth.context).canViewShifts();
  }

  static bool canAccessShiftCreate(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    return PermissionService(auth.context).canManageShifts();
  }

  static bool canAccessShiftDetail(AuthSessionState auth) {
    return canAccessShiftCalendar(auth);
  }

  /// Returns redirect when [location] is a shift route the session cannot access.
  static String? shiftRouteRedirect({required String location, required AuthSessionState auth}) {
    if (!isShiftRoute(location)) {
      return null;
    }

    if (!auth.isAuthenticated) {
      return AppRoutes.login;
    }

    if ((auth.context?.needsClinicSetup ?? true)) {
      return clinicSetupRoute;
    }

    final allowed = switch (location) {
      AppRoutes.shiftsNew => canAccessShiftCreate(auth),
      AppRoutes.shiftsCalendar => canAccessShiftCalendar(auth),
      _ when location.startsWith('${AppRoutes.shifts}/') => canAccessShiftDetail(auth),
      _ => false,
    };

    return allowed ? null : AppRoutes.home;
  }

  /// Returns redirect when [location] is a billing route the session cannot access.
  static String? billingRouteRedirect({required String location, required AuthSessionState auth}) {
    if (!isBillingRoute(location)) {
      return null;
    }

    if (!auth.isAuthenticated) {
      return AppRoutes.login;
    }

    if ((auth.context?.needsClinicSetup ?? true)) {
      return clinicSetupRoute;
    }

    final allowed = switch (location) {
      AppRoutes.billing => canAccessInvoiceList(auth) || canAccessBillingSettings(auth),
      AppRoutes.billingInvoices => canAccessInvoiceList(auth),
      AppRoutes.billingInsuranceProviders => canAccessInsuranceProviders(auth),
      AppRoutes.settingsBilling => canAccessBillingSettings(auth),
      _ when location.endsWith('/${AppRoutes.billingInvoiceEditSegment}') => canAccessInvoiceEdit(auth),
      _ when location.startsWith('${AppRoutes.billingInvoices}/') => canAccessInvoiceDetail(auth),
      _ => false,
    };

    return allowed ? null : AppRoutes.home;
  }

  /// Returns redirect when [location] is an appointment route the session cannot access.
  static String? appointmentRouteRedirect({required String location, required AuthSessionState auth}) {
    if (!isAppointmentRoute(location)) {
      return null;
    }

    if (!auth.isAuthenticated) {
      return AppRoutes.login;
    }

    if ((auth.context?.needsClinicSetup ?? true)) {
      return clinicSetupRoute;
    }

    final allowed = switch (location) {
      AppRoutes.appointmentsBook => canAccessAppointmentBooking(auth),
      _ when location.startsWith('${AppRoutes.appointments}/schedule/') => canAccessAppointmentHub(auth),
      _ => canAccessAppointmentHub(auth),
    };

    return allowed ? null : AppRoutes.home;
  }

  /// Returns redirect when [location] is a patient route the session cannot access.
  static String? patientRouteRedirect({required String location, required AuthSessionState auth}) {
    if (!isPatientRoute(location)) {
      return null;
    }

    if (!auth.isAuthenticated) {
      return AppRoutes.login;
    }

    if ((auth.context?.needsClinicSetup ?? true)) {
      return clinicSetupRoute;
    }

    // List/detail routes stay reachable; mutation affordances are gated in-page via
    // [canAccessPatientRegistration], [canAccessPatientEdit], and [canAccessPatientDelete].
    return null;
  }

  static bool isSettingsRoute(String location) {
    return location == AppRoutes.settings ||
        location == AppRoutes.settingsIdleTimeout ||
        location == AppRoutes.settingsBilling ||
        isServiceCatalogRoute(location) ||
        isAdminSettingsRoute(location);
  }

  /// Service catalog administration routes (015).
  static bool isServiceCatalogRoute(String location) {
    if (AppRoutes.serviceCatalogStaticPaths.contains(location)) {
      return true;
    }
    return location.startsWith('/settings/services/');
  }

  static bool canAccessServiceEditor(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    return PermissionService(auth.context).canManageServices();
  }

  static bool canAccessServiceCatalogList(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    final permissions = PermissionService(auth.context);
    return permissions.canViewServices() || permissions.canManageServices();
  }

  /// Returns redirect when [location] is a service catalog route the session cannot access.
  static String? serviceCatalogRouteRedirect({required String location, required AuthSessionState auth}) {
    if (!isServiceCatalogRoute(location)) {
      return null;
    }

    if (!auth.isAuthenticated) {
      return AppRoutes.login;
    }

    if ((auth.context?.needsClinicSetup ?? true)) {
      return clinicSetupRoute;
    }

    final allowed = switch (location) {
      AppRoutes.settingsServices => canAccessServiceCatalogList(auth),
      AppRoutes.settingsServicesNew => canAccessServiceEditor(auth),
      _ when location.startsWith('/settings/services/') => canAccessServiceEditor(auth),
      _ => false,
    };

    return allowed ? null : AppRoutes.settings;
  }

  /// V1-2 clinic management hub at `/clinic-management`.
  static bool isClinicManagementRoute(String location) {
    return location == AppRoutes.clinicManagement;
  }

  /// V1-2 administration sub-routes under the settings hub.
  static bool isAdminSettingsRoute(String location) {
    if (AppRoutes.adminSettingsPaths.contains(location)) {
      return true;
    }
    if (location.startsWith('${AppRoutes.settingsBranches}/') && location.endsWith('/edit')) {
      return true;
    }
    if (location.startsWith('${AppRoutes.settingsStaff}/') && location != AppRoutes.settingsStaffNew) {
      return true;
    }
    return false;
  }

  static bool canAccessOrganizationSettings(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    final context = auth.context;
    if (context == null) {
      return false;
    }
    return context.staffProfile.role == StaffRole.administrator;
  }

  static bool canAccessBranchManagement(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    final context = auth.context;
    if (context == null) {
      return false;
    }
    return context.permissions.contains(PermissionKeys.manageBranches);
  }

  /// Clinic setup tab: organization profile and/or branch administration.
  static bool canAccessClinicSetup(AuthSessionState auth) {
    return canAccessOrganizationSettings(auth) || canAccessBranchManagement(auth);
  }

  static bool canAccessStaffManagement(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    final context = auth.context;
    if (context == null) {
      return false;
    }
    return context.permissions.contains(PermissionKeys.manageStaff);
  }

  static bool canAccessPermissionMatrix(AuthSessionState auth) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return false;
    }
    final context = auth.context;
    if (context == null) {
      return false;
    }
    return context.staffProfile.role == StaffRole.administrator;
  }

  /// Returns redirect target when [location] is an admin settings route the session cannot access.
  static String? adminSettingsRedirect({required String location, required AuthSessionState auth}) {
    if (!isAdminSettingsRoute(location)) {
      return null;
    }

    if (!auth.isAuthenticated) {
      return AppRoutes.login;
    }

    if ((auth.context?.needsClinicSetup ?? true)) {
      return clinicSetupRoute;
    }

    final allowed = switch (location) {
      AppRoutes.settingsOrganization => canAccessOrganizationSettings(auth),
      AppRoutes.settingsBranches || AppRoutes.settingsBranchesNew => canAccessBranchManagement(auth),
      AppRoutes.settingsStaff || AppRoutes.settingsStaffNew => canAccessStaffManagement(auth),
      AppRoutes.settingsPermissions => canAccessPermissionMatrix(auth),
      _ when location.startsWith('${AppRoutes.settingsBranches}/') => canAccessBranchManagement(auth),
      _ when location.startsWith('${AppRoutes.settingsStaff}/') => canAccessStaffManagement(auth),
      _ => false,
    };

    return allowed ? null : AppRoutes.settings;
  }

  /// Returns redirect when [location] is the clinic management hub the session cannot access.
  static String? clinicManagementRouteRedirect({required String location, required AuthSessionState auth}) {
    if (!isClinicManagementRoute(location)) {
      return null;
    }

    if (!auth.isAuthenticated) {
      return AppRoutes.login;
    }

    if (auth.context!.setupRequired) {
      return AppRoutes.bootstrap;
    }

    final allowed =
        canAccessOrganizationSettings(auth) ||
        canAccessBranchManagement(auth) ||
        canAccessStaffManagement(auth) ||
        canAccessPermissionMatrix(auth);

    return allowed ? null : AppRoutes.home;
  }

  /// Staff account administration routes (blocked until clinic bootstrap completes).
  static bool isStaffProvisioningRoute(String location) {
    return location == AppRoutes.staffCreate || location == AppRoutes.staffPasswordReset;
  }

  /// Redirects V1-1 minimal provisioning routes to settings administration when setup is complete (US6).
  static String? steadyStateProvisioningRedirect({required String location, required AuthSessionState auth}) {
    if (!auth.isAuthenticated || (auth.context?.needsClinicSetup ?? true)) {
      return null;
    }

    if (location == AppRoutes.staffCreate) {
      return canAccessStaffManagement(auth) ? AppRoutes.clinicManagement : AppRoutes.settings;
    }

    if (location == AppRoutes.staffPasswordReset) {
      return canAccessStaffManagement(auth) ? AppRoutes.clinicManagement : AppRoutes.settings;
    }

    return null;
  }

  /// Whether a protected feature route may render (authenticated + setup complete).
  static bool canAccessProtectedFeatureRoute(AuthSessionState auth) {
    if (!auth.isAuthenticated) {
      return false;
    }

    return !(auth.context?.needsClinicSetup ?? true);
  }

  /// Post-login destination from JWT `setup_required` (see `contracts/auth-session.md`).
  static String postLoginDestination(AuthSessionState auth) {
    if (!auth.isAuthenticated) {
      return AppRoutes.login;
    }

    return (auth.context?.needsClinicSetup ?? true) ? clinicSetupRoute : AppRoutes.home;
  }

  /// Returns a redirect target path, or `null` when [location] may render.
  static String? resolveRedirect({
    required String location,
    required AuthSessionState auth,
    bool bootstrapStaffWizardInProgress = false,
  }) {
    final redirect = _resolveRedirect(
      location: location,
      auth: auth,
      bootstrapStaffWizardInProgress: bootstrapStaffWizardInProgress,
    );
    if (redirect != null) {
      AppLog.fine('auth.route.redirect from=$location to=$redirect');
    }
    return redirect;
  }

  static String? _resolveRedirect({
    required String location,
    required AuthSessionState auth,
    bool bootstrapStaffWizardInProgress = false,
  }) {
    if (auth.status == AuthSessionStatus.unknown || auth.status == AuthSessionStatus.loading) {
      // Treat an unresolved session like unauthenticated for non-public routes so a
      // deep link cannot render AuthenticatedShell with enabled chrome before auth
      // resolves. Public routes (login/forgot-password/startup) are left through.
      if (isPublicUnauthenticatedRoute(location)) {
        return null;
      }
      return AppRoutes.login;
    }

    if (auth.isAuthenticated) {
      if (auth.context?.needsClinicSetup ?? true) {
        if (location == clinicSetupRoute) {
          return null;
        }

        return clinicSetupRoute;
      }

      if (location == AppRoutes.login || location == AppRoutes.bootstrap || location == AppRoutes.forgotPassword) {
        if (bootstrapStaffWizardInProgress && location == AppRoutes.home) {
          return null;
        }
        if (location == AppRoutes.bootstrap && bootstrapStaffWizardInProgress) {
          return null;
        }
        return AppRoutes.home;
      }

      final steadyStateProvisioning = steadyStateProvisioningRedirect(location: location, auth: auth);
      if (steadyStateProvisioning != null) {
        return steadyStateProvisioning;
      }

      return null;
    }

    if (isPublicUnauthenticatedRoute(location)) {
      return null;
    }

    if (requiresAuthentication(location)) {
      return AppRoutes.login;
    }

    return AppRoutes.login;
  }

  static bool requiresProtectedSetupComplete(String location) {
    return location.startsWith('${AppRoutes.protectedPrefix}/');
  }
}
