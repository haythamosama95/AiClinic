import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Route guard rules for auth session states (see `contracts/auth-session.md`).
abstract final class AuthRouteGuard {
  /// Routes reachable without an authenticated session.
  static bool isPublicUnauthenticatedRoute(String location) {
    return location == AppRoutes.startupEntry ||
        location == AppRoutes.startupCheck ||
        location == AppRoutes.setupGuidance ||
        location == AppRoutes.protectedBlocked ||
        location == AppRoutes.foundationDemo ||
        location == AppRoutes.login ||
        location == AppRoutes.forgotPassword;
  }

  /// Routes that require a signed-in staff session.
  static bool requiresAuthentication(String location) {
    return location == AppRoutes.home ||
        location == AppRoutes.bootstrap ||
        isSettingsRoute(location) ||
        isPatientRoute(location) ||
        isAppointmentRoute(location) ||
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
    if (!auth.isAuthenticated || auth.context!.setupRequired) {
      return false;
    }
    return PermissionService(auth.context).canViewPatients();
  }

  static bool canAccessPatientRegistration(AuthSessionState auth) {
    if (!auth.isAuthenticated || auth.context!.setupRequired) {
      return false;
    }
    return PermissionService(auth.context).canCreatePatients();
  }

  static bool canAccessPatientDetail(AuthSessionState auth) {
    return canAccessPatientList(auth);
  }

  static bool canAccessPatientEdit(AuthSessionState auth) {
    if (!auth.isAuthenticated || auth.context!.setupRequired) {
      return false;
    }
    return PermissionService(auth.context).canEditPatients();
  }

  /// V1-4 appointment routes under `/appointments`.
  static bool isAppointmentRoute(String location) {
    return location == AppRoutes.appointments || location.startsWith('${AppRoutes.appointments}/');
  }

  static bool canAccessAppointmentHub(AuthSessionState auth) {
    if (!auth.isAuthenticated || auth.context!.setupRequired) {
      return false;
    }
    return PermissionService(auth.context).canAccessAppointments();
  }

  static bool canAccessAppointmentBooking(AuthSessionState auth) {
    if (!auth.isAuthenticated || auth.context!.setupRequired) {
      return false;
    }
    return PermissionService(auth.context).canCreateAppointments();
  }

  static bool canAccessAppointmentCancelActions(AuthSessionState auth) {
    if (!auth.isAuthenticated || auth.context!.setupRequired) {
      return false;
    }
    return PermissionService(auth.context).canCancelAppointments();
  }

  /// Returns redirect when [location] is an appointment route the session cannot access.
  static String? appointmentRouteRedirect({required String location, required AuthSessionState auth}) {
    if (!isAppointmentRoute(location)) {
      return null;
    }

    if (!auth.isAuthenticated) {
      return AppRoutes.login;
    }

    if (auth.context!.setupRequired) {
      return AppRoutes.bootstrap;
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

    if (auth.context!.setupRequired) {
      return AppRoutes.bootstrap;
    }

    // Permission checks are enforced on each patient page (UI stays visible; denial in-page).
    return null;
  }

  static bool isSettingsRoute(String location) {
    return location == AppRoutes.settings ||
        location == AppRoutes.settingsIdleTimeout ||
        isAdminSettingsRoute(location);
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
    if (!auth.isAuthenticated || auth.context!.setupRequired) {
      return false;
    }
    final role = auth.context!.staffProfile.role;
    return role == StaffRole.owner || role == StaffRole.administrator;
  }

  static bool canAccessBranchManagement(AuthSessionState auth) {
    if (!auth.isAuthenticated || auth.context!.setupRequired) {
      return false;
    }
    return auth.context!.permissions.contains(PermissionKeys.manageBranches);
  }

  static bool canAccessStaffManagement(AuthSessionState auth) {
    if (!auth.isAuthenticated || auth.context!.setupRequired) {
      return false;
    }
    return auth.context!.permissions.contains(PermissionKeys.manageStaff);
  }

  static bool canAccessPermissionMatrix(AuthSessionState auth) {
    if (!auth.isAuthenticated || auth.context!.setupRequired) {
      return false;
    }
    final role = auth.context!.staffProfile.role;
    return role == StaffRole.owner || role == StaffRole.administrator;
  }

  /// Returns redirect target when [location] is an admin settings route the session cannot access.
  static String? adminSettingsRedirect({required String location, required AuthSessionState auth}) {
    if (!isAdminSettingsRoute(location)) {
      return null;
    }

    if (!auth.isAuthenticated) {
      return AppRoutes.login;
    }

    if (auth.context!.setupRequired) {
      return AppRoutes.bootstrap;
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

  /// Staff account administration routes (blocked until clinic bootstrap completes).
  static bool isStaffProvisioningRoute(String location) {
    return location == AppRoutes.staffCreate || location == AppRoutes.staffPasswordReset;
  }

  /// Redirects V1-1 minimal provisioning routes to settings administration when setup is complete (US6).
  static String? steadyStateProvisioningRedirect({required String location, required AuthSessionState auth}) {
    if (!auth.isAuthenticated || auth.context!.setupRequired) {
      return null;
    }

    if (location == AppRoutes.staffCreate) {
      return canAccessStaffManagement(auth) ? AppRoutes.settingsStaffNew : AppRoutes.settings;
    }

    if (location == AppRoutes.staffPasswordReset) {
      return canAccessStaffManagement(auth) ? AppRoutes.settingsStaff : AppRoutes.settings;
    }

    return null;
  }

  /// Whether a protected feature route may render (authenticated + setup complete).
  static bool canAccessProtectedFeatureRoute(AuthSessionState auth) {
    if (!auth.isAuthenticated) {
      return false;
    }

    return !auth.context!.setupRequired;
  }

  /// Returns a redirect target path, or `null` when [location] may render.
  static String? resolveRedirect({required String location, required AuthSessionState auth}) {
    final redirect = _resolveRedirect(location: location, auth: auth);
    if (redirect != null) {
      AppLog.fine('auth.route.redirect from=$location to=$redirect');
    }
    return redirect;
  }

  static String? _resolveRedirect({required String location, required AuthSessionState auth}) {
    if (auth.status == AuthSessionStatus.unknown || auth.status == AuthSessionStatus.loading) {
      return null;
    }

    if (auth.isAuthenticated) {
      final context = auth.context!;
      if (context.setupRequired) {
        if (location == AppRoutes.bootstrap) {
          return null;
        }

        if (location == AppRoutes.home ||
            requiresProtectedSetupComplete(location) ||
            isStaffProvisioningRoute(location) ||
            isSettingsRoute(location)) {
          return AppRoutes.bootstrap;
        }

        if (location == AppRoutes.login || location == AppRoutes.forgotPassword) {
          return AppRoutes.bootstrap;
        }

        return null;
      }

      if (location == AppRoutes.login || location == AppRoutes.bootstrap || location == AppRoutes.forgotPassword) {
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
