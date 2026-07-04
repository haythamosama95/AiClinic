import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/presentation/ui_pending_placeholder_page.dart';
import 'package:ai_clinic/features/dev/presentation/pages/theme_showcase_page.dart';
import 'package:ai_clinic/features/appointments/presentation/navigation/appointment_detail_route_extra.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_hub_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_queue_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_booking_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_detail_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/doctor_schedule_page.dart';
import 'package:ai_clinic/features/auth/presentation/pages/login_page.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_list_page.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_detail_page.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_editor_page.dart';
import 'package:ai_clinic/features/billing/presentation/pages/insurance_providers_page.dart';
import 'package:ai_clinic/features/billing/presentation/pages/billing_settings_page.dart';
import 'package:ai_clinic/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:ai_clinic/features/patients/presentation/navigation/patient_detail_route_extra.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patients_list_page.dart';
import 'package:ai_clinic/features/patients/presentation/pages/register_patient_page.dart';
import 'package:ai_clinic/features/patients/presentation/pages/edit_patient_page.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_detail_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/settings_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/idle_timeout_settings_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/organization_settings_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/branches_list_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/branch_create_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/branch_edit_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/staff_list_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/staff_create_settings_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/staff_detail_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/staff_reset_password_settings_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/role_permissions_page.dart';
import 'package:ai_clinic/features/service_catalog/presentation/pages/service_catalog_list_page.dart';
import 'package:ai_clinic/features/service_catalog/presentation/pages/service_editor_create_page.dart';
import 'package:ai_clinic/features/service_catalog/presentation/pages/service_editor_edit_page.dart';
import 'package:ai_clinic/features/setup/presentation/pages/bootstrap_wizard_page.dart';
import 'package:ai_clinic/features/shifts/presentation/pages/shift_calendar_page.dart';
import 'package:ai_clinic/features/shifts/presentation/pages/shift_create_page.dart';
import 'package:ai_clinic/features/shifts/presentation/pages/shift_detail_page.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_documentation_page.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_detail_page.dart';
import 'package:ai_clinic/features/setup/presentation/pages/staff_create_page.dart';
import 'package:ai_clinic/features/setup/presentation/pages/staff_password_reset_page.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';
import 'package:ai_clinic/app/shell/authenticated_shell.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/startup_session_provider.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_integration.dart';

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
    initialLocation: AppRoutes.startupCheck,
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
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => LoginPage(forgotMode: state.uri.queryParameters.containsKey('forgot')),
      ),
      GoRoute(path: AppRoutes.forgotPassword, redirect: (context, state) => '${AppRoutes.login}?forgot=1'),
      GoRoute(path: AppRoutes.bootstrap, builder: (context, state) => const BootstrapWizardPage()),
      GoRoute(path: AppRoutes.staffCreate, builder: (context, state) => const StaffCreatePage()),
      GoRoute(path: AppRoutes.staffPasswordReset, builder: (context, state) => const StaffPasswordResetPage()),

      // Authenticated shell — shared navigation wraps all feature routes
      ShellRoute(
        builder: (context, state, child) => AuthenticatedShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.foundationDemo,
            builder: (context, state) => const ThemeShowcasePage(),
          ),
          GoRoute(path: AppRoutes.home, builder: (context, state) => const DashboardPage()),

          // Patient management
          GoRoute(path: AppRoutes.patients, builder: (context, state) => const PatientsListPage()),
          GoRoute(path: AppRoutes.patientsNew, builder: (context, state) => const RegisterPatientPage()),
          GoRoute(
            path: '${AppRoutes.patients}/:patientId',
            builder: (context, state) => PatientDetailPage(
              patientId: state.pathParameters['patientId']!,
              preview: PatientDetailRouteExtra.fromExtra(state.extra).preview,
            ),
          ),
          GoRoute(
            path: '${AppRoutes.patients}/:patientId/edit',
            builder: (context, state) => EditPatientPage(patientId: state.pathParameters['patientId']!),
          ),

          // Appointments (V1-4)
          GoRoute(
            path: AppRoutes.appointments,
            builder: (context, state) => const AppointmentHubPage(),
          ),
          GoRoute(
            path: AppRoutes.appointmentsBook,
            builder: (context, state) => const AppointmentBookingPage(),
          ),
          GoRoute(
            path: AppRoutes.appointmentsQueue,
            builder: (context, state) => const AppointmentQueuePage(),
          ),
          GoRoute(
            path: AppRoutes.appointmentsCalendar,
            builder: (context, state) => const AppointmentCalendarPage(),
          ),
          GoRoute(
            path: '${AppRoutes.appointments}/:appointmentId',
            builder: (context, state) => AppointmentDetailPage(
              appointmentId: state.pathParameters['appointmentId']!,
              preview: AppointmentDetailRouteExtra.fromExtra(state.extra).preview,
            ),
          ),
          GoRoute(
            path: '${AppRoutes.appointments}/schedule/:doctorId',
            builder: (context, state) => DoctorSchedulePage(doctorId: state.pathParameters['doctorId']!),
          ),

          // Visits (V1-5)
          GoRoute(
            path: '${AppRoutes.visits}/:visitId/${AppRoutes.visitDocumentSegment}',
            builder: (context, state) => VisitDocumentationPage(
              visitId: state.pathParameters['visitId']!,
              startEditing: state.uri.queryParameters['edit'] == '1',
            ),
          ),
          GoRoute(
            path: '${AppRoutes.visits}/:visitId/${AppRoutes.visitDetailSegment}',
            builder: (context, state) => VisitDetailPage(visitId: state.pathParameters['visitId']!),
          ),

          // Billing (V1-6)
          GoRoute(path: AppRoutes.billingInvoices, builder: (context, state) => const InvoiceListPage()),
          GoRoute(
            path: '${AppRoutes.billingInvoices}/:invoiceId/${AppRoutes.billingInvoiceEditSegment}',
            builder: (context, state) => InvoiceEditorPage(invoiceId: state.pathParameters['invoiceId']!),
          ),
          GoRoute(
            path: '${AppRoutes.billingInvoices}/:invoiceId',
            builder: (context, state) => InvoiceDetailPage(invoiceId: state.pathParameters['invoiceId']!),
          ),
          GoRoute(
            path: AppRoutes.billingInsuranceProviders,
            builder: (context, state) => const InsuranceProvidersPage(),
          ),
          GoRoute(path: AppRoutes.settingsBilling, builder: (context, state) => const BillingSettingsPage()),
          GoRoute(
            path: AppRoutes.settingsServices,
            builder: (context, state) => const ServiceCatalogListPage(),
          ),
          GoRoute(
            path: AppRoutes.settingsServicesNew,
            builder: (context, state) => const ServiceEditorCreatePage(),
          ),
          GoRoute(
            path: '/settings/services/:serviceId/edit',
            builder: (context, state) => ServiceEditorEditPage(serviceId: state.pathParameters['serviceId']!),
          ),

          // Shifts (V1-7)
          GoRoute(path: AppRoutes.shiftsCalendar, builder: (context, state) => const ShiftCalendarPage()),
          GoRoute(path: AppRoutes.shiftsNew, builder: (context, state) => const ShiftCreatePage()),
          GoRoute(
            path: '${AppRoutes.shifts}/:shiftId',
            builder: (context, state) => ShiftDetailPage(shiftId: state.pathParameters['shiftId']!),
          ),

          // Settings
          GoRoute(path: AppRoutes.settings, builder: (context, state) => const SettingsPage()),
          GoRoute(
            path: AppRoutes.settingsIdleTimeout,
            builder: (context, state) => const IdleTimeoutSettingsPage(),
          ),
          GoRoute(
            path: AppRoutes.settingsOrganization,
            builder: (context, state) => const OrganizationSettingsPage(),
          ),
          GoRoute(
            path: AppRoutes.settingsBranches,
            builder: (context, state) => const BranchesListPage(),
          ),
          GoRoute(
            path: AppRoutes.settingsBranchesNew,
            builder: (context, state) => const BranchCreatePage(),
          ),
          GoRoute(
            path: '${AppRoutes.settingsBranches}/:branchId/edit',
            builder: (context, state) => BranchEditPage(branchId: state.pathParameters['branchId']!),
          ),
          GoRoute(path: AppRoutes.settingsStaff, builder: (context, state) => const StaffListPage()),
          GoRoute(
            path: AppRoutes.settingsStaffNew,
            builder: (context, state) => const SettingsStaffCreatePage(),
          ),
          GoRoute(
            path: '${AppRoutes.settingsStaff}/:staffId',
            builder: (context, state) => StaffDetailPage(staffId: state.pathParameters['staffId']!),
          ),
          GoRoute(
            path: '${AppRoutes.settingsStaff}/:staffId/reset-password',
            builder: (context, state) =>
                StaffResetPasswordSettingsPage(staffId: state.pathParameters['staffId']!),
          ),
          GoRoute(
            path: AppRoutes.settingsPermissions,
            builder: (context, state) => const RolePermissionsPage(),
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      final session = ref.read(startupSessionProvider);
      final auth = ref.read(authSessionProvider);
      final setup = ref.read(setupNotifierProvider);
      final location = state.matchedLocation;

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
