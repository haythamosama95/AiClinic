import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/design_reference_mode.dart';
import 'package:ai_clinic/app/presentation/shell_dev_page.dart';
import 'package:ai_clinic/app/presentation/shell_placeholder_page.dart';
import 'package:ai_clinic/app/presentation/ui_pending_placeholder_page.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';
import 'package:ai_clinic/app/shell/authenticated_shell.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/startup_session_provider.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_integration.dart';
import 'package:ai_clinic/app/shell/shell_nav.dart';

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

  shellDevListenForRouterRefresh(ref, () => refreshSignal.value++);

  final notifier = ref.read(startupSessionProvider.notifier);

  return GoRouter(
    initialLocation: isDesignReferenceMode ? AppRoutes.home : AppRoutes.startupCheck,
    refreshListenable: refreshSignal,
    routes: [
      // Unauthenticated / startup routes
      GoRoute(path: AppRoutes.startupCheck, builder: (context, state) => uiPendingPlaceholder('Startup', state)),
      GoRoute(path: AppRoutes.startupEntry, builder: (context, state) => uiPendingPlaceholder('Startup', state)),
      GoRoute(path: AppRoutes.setupGuidance, builder: (context, state) => uiPendingPlaceholder('Startup', state)),
      GoRoute(path: AppRoutes.protectedBlocked, builder: (context, state) => uiPendingPlaceholder('Startup', state)),
      GoRoute(
        path: AppRoutes.protectedPlaceholder,
        builder: (context, state) => uiPendingPlaceholder('Startup', state),
      ),
      GoRoute(path: AppRoutes.login, builder: (context, state) => uiPendingPlaceholder('Auth', state)),
      GoRoute(path: AppRoutes.forgotPassword, redirect: (context, state) => '${AppRoutes.login}?forgot=1'),
      GoRoute(path: AppRoutes.bootstrap, builder: (context, state) => uiPendingPlaceholder('Setup', state)),
      GoRoute(path: AppRoutes.staffCreate, builder: (context, state) => uiPendingPlaceholder('Setup', state)),
      GoRoute(path: AppRoutes.staffPasswordReset, builder: (context, state) => uiPendingPlaceholder('Setup', state)),
      GoRoute(
        path: AppRoutes.foundationDemo,
        redirect: (context, state) => AppRoutes.devFoundations,
      ),

      // Authenticated shell — shared navigation wraps all feature routes
      ShellRoute(
        builder: (context, state, child) => AuthenticatedShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const ShellPlaceholderPage(navId: 'home'),
          ),
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (context, state) => const ShellPlaceholderPage(navId: 'dashboard'),
          ),
          GoRoute(
            path: AppRoutes.encounters,
            builder: (context, state) => const ShellPlaceholderPage(navId: 'encounters'),
          ),
          GoRoute(
            path: AppRoutes.workspace,
            builder: (context, state) => const ShellPlaceholderPage(navId: 'workspace'),
          ),
          GoRoute(
            path: AppRoutes.reports,
            builder: (context, state) => const ShellPlaceholderPage(navId: 'reports'),
          ),
          GoRoute(
            path: AppRoutes.billingHub,
            builder: (context, state) => const ShellPlaceholderPage(navId: 'billing'),
          ),
          GoRoute(
            path: AppRoutes.dev,
            redirect: (context, state) => AppRoutes.devFoundations,
          ),
          GoRoute(
            path: AppRoutes.devFoundations,
            builder: (context, state) =>
                const ShellDevPage(section: ShellDevSection.foundations),
          ),
          GoRoute(
            path: AppRoutes.devComponents,
            builder: (context, state) =>
                const ShellDevPage(section: ShellDevSection.components),
          ),

          // Patient management — list route is shell placeholder (web `#patients`)
          GoRoute(
            path: AppRoutes.patients,
            builder: (context, state) => const ShellPlaceholderPage(navId: 'patients'),
          ),
          GoRoute(path: AppRoutes.patientsNew, builder: (context, state) => uiPendingPlaceholder('Patients', state)),
          GoRoute(
            path: '${AppRoutes.patients}/:patientId',
            builder: (context, state) => uiPendingPlaceholder('Patients', state),
          ),
          GoRoute(
            path: '${AppRoutes.patients}/:patientId/edit',
            builder: (context, state) => uiPendingPlaceholder('Patients', state),
          ),

          // Appointments (V1-4) — hub is shell placeholder (web `#appointments`)
          GoRoute(
            path: AppRoutes.appointments,
            builder: (context, state) => const ShellPlaceholderPage(navId: 'appointments'),
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
            path: '${AppRoutes.appointments}/:appointmentId',
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

          // Billing (V1-6) — invoices list is shell placeholder (web `#invoices`)
          GoRoute(
            path: AppRoutes.billingInvoices,
            builder: (context, state) => const ShellPlaceholderPage(navId: 'invoices'),
          ),
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
          GoRoute(
            path: AppRoutes.settingsServices,
            builder: (context, state) => const ShellPlaceholderPage(navId: 'services'),
          ),
          GoRoute(
            path: AppRoutes.settingsServicesNew,
            builder: (context, state) => uiPendingPlaceholder('Service Catalog', state),
          ),
          GoRoute(
            path: '/settings/services/:serviceId/edit',
            builder: (context, state) => uiPendingPlaceholder('Service Catalog', state),
          ),

          // Shifts (V1-7) — calendar hub is shell placeholder (web `#shifts`)
          GoRoute(
            path: AppRoutes.shiftsCalendar,
            builder: (context, state) => const ShellPlaceholderPage(navId: 'shifts'),
          ),
          GoRoute(path: AppRoutes.shiftsNew, builder: (context, state) => uiPendingPlaceholder('Shifts', state)),
          GoRoute(
            path: '${AppRoutes.shifts}/:shiftId',
            builder: (context, state) => uiPendingPlaceholder('Shifts', state),
          ),

          // Settings — hub is shell placeholder (web `#settings`)
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => const ShellPlaceholderPage(navId: 'settings'),
          ),
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
          GoRoute(
            path: AppRoutes.settingsStaff,
            builder: (context, state) => const ShellPlaceholderPage(navId: 'staff'),
          ),
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
          GoRoute(
            path: AppRoutes.settingsPermissions,
            builder: (context, state) => uiPendingPlaceholder('Settings', state),
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      final session = ref.read(startupSessionProvider);
      final auth = ref.read(authSessionProvider);
      final setup = ref.read(setupNotifierProvider);
      final location = state.matchedLocation;

      // Legacy standalone showcase path forwards into the shelled dev route.
      if (location == AppRoutes.foundationDemo) {
        return AppRoutes.devFoundations;
      }

      // Design reference: shell routes are public (mirrors web App.tsx — no auth).
      if (isDesignReferenceMode && isShellNavLocation(location)) {
        return null;
      }

      if (shellDevSuppressAuthRedirect(ref, auth)) {
        return null;
      }

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
        StartupCurrentView.startupCheck => () {
          if (isDesignReferenceMode && location == AppRoutes.home) {
            return null;
          }
          return location == AppRoutes.startupCheck ? null : AppRoutes.startupCheck;
        }(),
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

          if (isDesignReferenceMode) {
            if (location == AppRoutes.startupCheck ||
                location == AppRoutes.startupEntry ||
                location == AppRoutes.login) {
              return AppRoutes.home;
            }
            if (isShellNavLocation(location)) {
              return null;
            }
          }

          // Legacy landing routes remain registered but are not reachable in normal flow.
          if (location == AppRoutes.startupEntry) {
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

        final serviceCatalogRedirect = AuthRouteGuard.serviceCatalogRouteRedirect(location: location, auth: auth);
        if (serviceCatalogRedirect != null) {
          return serviceCatalogRedirect;
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
