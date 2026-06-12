import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/presentation/startup_entry_page.dart';
import 'package:ai_clinic/app/presentation/ui_pending_placeholder_page.dart';
import 'package:ai_clinic/features/auth/presentation/pages/login_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/role_permissions_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/settings_page.dart';
import 'package:ai_clinic/features/setup/presentation/pages/setup_page.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';
import 'package:ai_clinic/core/ui/demo/theme_showcase_page.dart';
import 'package:ai_clinic/app/shell/authenticated_shell.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/startup_session_provider.dart';

/// Rebuilds router redirects whenever startup or auth session state changes.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshSignal = ValueNotifier<int>(0);
  ref.onDispose(refreshSignal.dispose);
  ref.listen<StartupSessionState>(startupSessionProvider, (_, _) {
    refreshSignal.value++;
  });
  ref.listen<AuthSessionState>(authSessionProvider, (_, _) {
    refreshSignal.value++;
  });
  ref.listen<SetupUiState>(setupNotifierProvider, (_, _) {
    refreshSignal.value++;
  });

  final notifier = ref.read(startupSessionProvider.notifier);

  return GoRouter(
    initialLocation: AppRoutes.startupCheck,
    refreshListenable: refreshSignal,
    routes: [
      // Unauthenticated / startup routes
      GoRoute(path: AppRoutes.startupCheck, builder: (context, state) => uiPendingPlaceholder('Startup', state)),
      GoRoute(path: AppRoutes.startupEntry, builder: (context, state) => const StartupEntryPage()),
      GoRoute(path: AppRoutes.setupGuidance, builder: (context, state) => uiPendingPlaceholder('Startup', state)),
      GoRoute(path: AppRoutes.protectedBlocked, builder: (context, state) => uiPendingPlaceholder('Startup', state)),
      GoRoute(
        path: AppRoutes.protectedPlaceholder,
        builder: (context, state) => uiPendingPlaceholder('Startup', state),
      ),
      GoRoute(path: AppRoutes.login, builder: (context, state) => const LoginPage()),
      GoRoute(path: AppRoutes.forgotPassword, redirect: (context, state) => '${AppRoutes.login}?forgot=1'),
      GoRoute(path: AppRoutes.bootstrap, builder: (context, state) => const SetupPage()),
      GoRoute(path: AppRoutes.staffCreate, builder: (context, state) => uiPendingPlaceholder('Setup', state)),
      GoRoute(path: AppRoutes.staffPasswordReset, builder: (context, state) => uiPendingPlaceholder('Setup', state)),

      // Authenticated shell — shared navigation wraps all feature routes
      ShellRoute(
        builder: (context, state, child) => AuthenticatedShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.foundationDemo,
            builder: (context, state) => const ThemeShowcasePage(embeddedInShell: true),
          ),
          GoRoute(path: AppRoutes.home, builder: (context, state) => uiPendingPlaceholder('Auth', state)),

          // Patient management
          GoRoute(path: AppRoutes.patients, builder: (context, state) => uiPendingPlaceholder('Patients', state)),
          GoRoute(path: AppRoutes.patientsNew, builder: (context, state) => uiPendingPlaceholder('Patients', state)),
          GoRoute(
            path: '${AppRoutes.patients}/:patientId',
            builder: (context, state) => uiPendingPlaceholder('Patients', state),
          ),
          GoRoute(
            path: '${AppRoutes.patients}/:patientId/edit',
            builder: (context, state) => uiPendingPlaceholder('Patients', state),
          ),

          // Appointments (V1-4)
          GoRoute(
            path: AppRoutes.appointments,
            builder: (context, state) => uiPendingPlaceholder('Appointments', state),
          ),
          GoRoute(
            path: AppRoutes.appointmentsBook,
            builder: (context, state) => uiPendingPlaceholder('Appointments', state),
          ),
          GoRoute(
            path: AppRoutes.appointmentsQueue,
            builder: (context, state) => uiPendingPlaceholder('Appointments', state),
          ),
          GoRoute(
            path: AppRoutes.appointmentsCalendar,
            builder: (context, state) => uiPendingPlaceholder('Appointments', state),
          ),
          GoRoute(
            path: '${AppRoutes.appointments}/schedule/:doctorId',
            builder: (context, state) => uiPendingPlaceholder('Appointments', state),
          ),

          // Visits (V1-5)
          GoRoute(
            path: '${AppRoutes.visits}/:visitId/${AppRoutes.visitDocumentSegment}',
            builder: (context, state) => uiPendingPlaceholder('Visits', state),
          ),
          GoRoute(
            path: '${AppRoutes.visits}/:visitId/${AppRoutes.visitDetailSegment}',
            builder: (context, state) => uiPendingPlaceholder('Visits', state),
          ),

          // Billing (V1-6)
          GoRoute(path: AppRoutes.billingInvoices, builder: (context, state) => uiPendingPlaceholder('Billing', state)),
          GoRoute(
            path: '${AppRoutes.billingInvoices}/:invoiceId/${AppRoutes.billingInvoiceEditSegment}',
            builder: (context, state) => uiPendingPlaceholder('Billing', state),
          ),
          GoRoute(
            path: '${AppRoutes.billingInvoices}/:invoiceId',
            builder: (context, state) => uiPendingPlaceholder('Billing', state),
          ),
          GoRoute(
            path: AppRoutes.billingInsuranceProviders,
            builder: (context, state) => uiPendingPlaceholder('Billing', state),
          ),
          GoRoute(path: AppRoutes.settingsBilling, builder: (context, state) => uiPendingPlaceholder('Billing', state)),

          // Shifts (V1-7)
          GoRoute(path: AppRoutes.shiftsCalendar, builder: (context, state) => uiPendingPlaceholder('Shifts', state)),
          GoRoute(path: AppRoutes.shiftsNew, builder: (context, state) => uiPendingPlaceholder('Shifts', state)),
          GoRoute(
            path: '${AppRoutes.shifts}/:shiftId',
            builder: (context, state) => uiPendingPlaceholder('Shifts', state),
          ),

          // Settings
          GoRoute(path: AppRoutes.settings, builder: (context, state) => const SettingsPage()),
          GoRoute(
            path: AppRoutes.settingsIdleTimeout,
            builder: (context, state) => uiPendingPlaceholder('Settings', state),
          ),
          GoRoute(
            path: AppRoutes.settingsOrganization,
            builder: (context, state) => uiPendingPlaceholder('Settings', state),
          ),
          GoRoute(
            path: AppRoutes.settingsBranches,
            builder: (context, state) => uiPendingPlaceholder('Settings', state),
          ),
          GoRoute(
            path: AppRoutes.settingsBranchesNew,
            builder: (context, state) => uiPendingPlaceholder('Settings', state),
          ),
          GoRoute(
            path: '${AppRoutes.settingsBranches}/:branchId/edit',
            builder: (context, state) => uiPendingPlaceholder('Settings', state),
          ),
          GoRoute(path: AppRoutes.settingsStaff, builder: (context, state) => uiPendingPlaceholder('Settings', state)),
          GoRoute(
            path: AppRoutes.settingsStaffNew,
            builder: (context, state) => uiPendingPlaceholder('Settings', state),
          ),
          GoRoute(
            path: '${AppRoutes.settingsStaff}/:staffId',
            builder: (context, state) => uiPendingPlaceholder('Settings', state),
          ),
          GoRoute(
            path: '${AppRoutes.settingsStaff}/:staffId/reset-password',
            builder: (context, state) => uiPendingPlaceholder('Settings', state),
          ),
          GoRoute(path: AppRoutes.settingsPermissions, builder: (context, state) => const RolePermissionsPage()),
        ],
      ),
    ],
    redirect: (context, state) {
      final session = ref.read(startupSessionProvider);
      final auth = ref.read(authSessionProvider);
      final setup = ref.read(setupNotifierProvider);
      final location = state.matchedLocation;

      String? resolveAuthRedirect(String route) => AuthRouteGuard.resolveRedirect(
        location: route,
        auth: auth,
        bootstrapStaffWizardInProgress: setup.isBootstrapWizardInProgress,
      );

      final isProtectedFeatureRoute = AuthRouteGuard.requiresProtectedSetupComplete(location);
      if (isProtectedFeatureRoute) {
        if (session.configurationStatus == StartupConfigurationStatus.valid) {
          final authTarget = resolveAuthRedirect(location);
          if (authTarget != null) {
            return authTarget;
          }

          if (!AuthRouteGuard.canAccessProtectedFeatureRoute(auth)) {
            return auth.isAuthenticated ? AppRoutes.bootstrap : AppRoutes.login;
          }
        }

        if (session.currentView != StartupCurrentView.protectedRouteBlocked) {
          notifier.blockProtectedRoute(location);
        }
        return AppRoutes.protectedBlocked;
      }

      final startupRedirect = switch (session.currentView) {
        StartupCurrentView.startupCheck => location == AppRoutes.startupCheck ? null : AppRoutes.startupCheck,
        StartupCurrentView.setupGuidance => location == AppRoutes.setupGuidance ? null : AppRoutes.setupGuidance,
        StartupCurrentView.protectedRouteBlocked =>
          location == AppRoutes.protectedBlocked ? null : AppRoutes.protectedBlocked,
        StartupCurrentView.unauthenticatedEntry => () {
          final authRedirect = resolveAuthRedirect(location);
          if (authRedirect != null) {
            return authRedirect;
          }

          if (auth.isAuthenticated) {
            return null;
          }

          // Legacy landing routes remain registered but are not reachable in normal flow.
          if (location == AppRoutes.startupEntry || location == AppRoutes.foundationDemo) {
            return AppRoutes.login;
          }

          const preAuthShellRoutes = {AppRoutes.login, AppRoutes.forgotPassword};
          return preAuthShellRoutes.contains(location) ? null : AppRoutes.login;
        }(),
      };

      if (startupRedirect != null) {
        return startupRedirect;
      }

      if (session.currentView == StartupCurrentView.unauthenticatedEntry) {
        final authRedirect = resolveAuthRedirect(location);
        if (authRedirect != null) {
          return authRedirect;
        }

        final adminRedirect = AuthRouteGuard.adminSettingsRedirect(location: location, auth: auth);
        if (adminRedirect != null) {
          return adminRedirect;
        }

        final patientRedirect = AuthRouteGuard.patientRouteRedirect(location: location, auth: auth);
        if (patientRedirect != null) {
          return patientRedirect;
        }

        final appointmentRedirect = AuthRouteGuard.appointmentRouteRedirect(location: location, auth: auth);
        if (appointmentRedirect != null) {
          return appointmentRedirect;
        }

        final visitRedirect = AuthRouteGuard.visitRouteRedirect(location: location, auth: auth);
        if (visitRedirect != null) {
          return visitRedirect;
        }

        final billingRedirect = AuthRouteGuard.billingRouteRedirect(location: location, auth: auth);
        if (billingRedirect != null) {
          return billingRedirect;
        }

        final shiftRedirect = AuthRouteGuard.shiftRouteRedirect(location: location, auth: auth);
        if (shiftRedirect != null) {
          return shiftRedirect;
        }

        final provisioningRedirect = AuthRouteGuard.steadyStateProvisioningRedirect(location: location, auth: auth);
        if (provisioningRedirect != null) {
          return provisioningRedirect;
        }

        return null;
      }

      return null;
    },
  );
});
