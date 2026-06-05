import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/authenticated_shell.dart';
import 'package:ai_clinic/features/auth/presentation/pages/auth_shell_page.dart';
import 'package:ai_clinic/features/auth/presentation/pages/clinic_bootstrap_page.dart';
import 'package:ai_clinic/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:ai_clinic/features/auth/presentation/pages/login_page.dart';
import 'package:ai_clinic/features/auth/presentation/pages/staff_create_page.dart';
import 'package:ai_clinic/features/auth/presentation/pages/staff_password_reset_page.dart';
import 'package:ai_clinic/features/foundation_demo/presentation/pages/foundation_demo_page.dart';
import 'package:ai_clinic/features/startup/presentation/pages/protected_placeholder_page.dart';
import 'package:ai_clinic/features/startup/presentation/pages/protected_route_blocked_page.dart';
import 'package:ai_clinic/features/startup/presentation/pages/setup_guidance_page.dart';
import 'package:ai_clinic/features/startup/presentation/pages/startup_check_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/idle_timeout_settings_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/branch_form_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/branch_list_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/organization_settings_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/role_permissions_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/settings_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/staff_form_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/staff_list_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/staff_settings_password_reset_page.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_pages.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_booking_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/doctor_schedule_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_hub_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_queue_page.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_detail_page.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_documentation_page.dart';
import 'package:ai_clinic/features/billing/presentation/pages/billing_settings_page.dart';
import 'package:ai_clinic/features/billing/presentation/pages/insurance_providers_page.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_detail_page.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_editor_page.dart';
import 'package:ai_clinic/features/billing/presentation/pages/invoice_list_page.dart';
import 'package:ai_clinic/features/startup/presentation/pages/startup_entry_page.dart';
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

  final notifier = ref.read(startupSessionProvider.notifier);

  return GoRouter(
    initialLocation: AppRoutes.startupCheck,
    refreshListenable: refreshSignal,
    routes: [
      // Unauthenticated / startup routes
      GoRoute(path: AppRoutes.startupCheck, builder: (context, state) => const StartupCheckPage()),
      GoRoute(path: AppRoutes.startupEntry, builder: (context, state) => const StartupEntryPage()),
      GoRoute(path: AppRoutes.setupGuidance, builder: (context, state) => const SetupGuidancePage()),
      GoRoute(path: AppRoutes.protectedBlocked, builder: (context, state) => const ProtectedRouteBlockedPage()),
      GoRoute(path: AppRoutes.protectedPlaceholder, builder: (context, state) => const ProtectedPlaceholderPage()),
      GoRoute(path: AppRoutes.foundationDemo, builder: (context, state) => const FoundationDemoPage()),
      GoRoute(path: AppRoutes.login, builder: (context, state) => const LoginPage()),
      GoRoute(path: AppRoutes.forgotPassword, builder: (context, state) => const ForgotPasswordPage()),
      GoRoute(path: AppRoutes.bootstrap, builder: (context, state) => const ClinicBootstrapPage()),
      GoRoute(path: AppRoutes.staffCreate, builder: (context, state) => const StaffCreatePage()),
      GoRoute(path: AppRoutes.staffPasswordReset, builder: (context, state) => const StaffPasswordResetPage()),

      // Authenticated shell — shared NavigationRail wraps all feature routes
      ShellRoute(
        builder: (context, state, child) => AuthenticatedShell(child: child),
        routes: [
          GoRoute(path: AppRoutes.home, builder: (context, state) => const AuthShellPage()),

          // Patient management
          GoRoute(path: AppRoutes.patients, builder: (context, state) => const PatientListPage()),
          GoRoute(path: AppRoutes.patientsNew, builder: (context, state) => const PatientRegistrationPage()),
          GoRoute(
            path: '${AppRoutes.patients}/:patientId',
            builder: (context, state) => PatientDetailPage(patientId: state.pathParameters['patientId']),
          ),
          GoRoute(
            path: '${AppRoutes.patients}/:patientId/edit',
            builder: (context, state) => PatientEditPage(patientId: state.pathParameters['patientId']),
          ),

          // Appointments (V1-4)
          GoRoute(path: AppRoutes.appointments, builder: (context, state) => const AppointmentHubPage()),
          GoRoute(path: AppRoutes.appointmentsBook, builder: (context, state) => const AppointmentBookingPage()),
          GoRoute(path: AppRoutes.appointmentsQueue, builder: (context, state) => const AppointmentQueuePage()),
          GoRoute(path: AppRoutes.appointmentsCalendar, builder: (context, state) => const AppointmentCalendarPage()),
          GoRoute(
            path: '${AppRoutes.appointments}/schedule/:doctorId',
            builder: (context, state) => DoctorSchedulePage(doctorId: state.pathParameters['doctorId']),
          ),

          // Visits (V1-5)
          GoRoute(
            path: '${AppRoutes.visits}/:visitId/${AppRoutes.visitDocumentSegment}',
            builder: (context, state) => VisitDocumentationPage(visitId: state.pathParameters['visitId']),
          ),
          GoRoute(
            path: '${AppRoutes.visits}/:visitId/${AppRoutes.visitDetailSegment}',
            builder: (context, state) => VisitDetailPage(visitId: state.pathParameters['visitId']),
          ),

          // Billing (V1-6)
          GoRoute(path: AppRoutes.billingInvoices, builder: (context, state) => const InvoiceListPage()),
          GoRoute(
            path: '${AppRoutes.billingInvoices}/:invoiceId/${AppRoutes.billingInvoiceEditSegment}',
            builder: (context, state) => InvoiceEditorPage(invoiceId: state.pathParameters['invoiceId']),
          ),
          GoRoute(
            path: '${AppRoutes.billingInvoices}/:invoiceId',
            builder: (context, state) => InvoiceDetailPage(invoiceId: state.pathParameters['invoiceId']),
          ),
          GoRoute(
            path: AppRoutes.billingInsuranceProviders,
            builder: (context, state) => const InsuranceProvidersPage(),
          ),
          GoRoute(path: AppRoutes.settingsBilling, builder: (context, state) => const BillingSettingsPage()),

          // Settings
          GoRoute(path: AppRoutes.settings, builder: (context, state) => const SettingsPage()),
          GoRoute(path: AppRoutes.settingsIdleTimeout, builder: (context, state) => const IdleTimeoutSettingsPage()),
          GoRoute(path: AppRoutes.settingsOrganization, builder: (context, state) => const OrganizationSettingsPage()),
          GoRoute(path: AppRoutes.settingsBranches, builder: (context, state) => const BranchListPage()),
          GoRoute(path: AppRoutes.settingsBranchesNew, builder: (context, state) => const BranchFormPage()),
          GoRoute(
            path: '${AppRoutes.settingsBranches}/:branchId/edit',
            builder: (context, state) => BranchFormPage(branchId: state.pathParameters['branchId']),
          ),
          GoRoute(path: AppRoutes.settingsStaff, builder: (context, state) => const StaffListPage()),
          GoRoute(path: AppRoutes.settingsStaffNew, builder: (context, state) => const StaffFormPage()),
          GoRoute(
            path: '${AppRoutes.settingsStaff}/:staffId',
            builder: (context, state) => StaffFormPage(staffId: state.pathParameters['staffId']),
          ),
          GoRoute(
            path: '${AppRoutes.settingsStaff}/:staffId/reset-password',
            builder: (context, state) => StaffSettingsPasswordResetPage(staffId: state.pathParameters['staffId']!),
          ),
          GoRoute(path: AppRoutes.settingsPermissions, builder: (context, state) => const RolePermissionsPage()),
        ],
      ),
    ],
    redirect: (context, state) {
      final session = ref.read(startupSessionProvider);
      final auth = ref.read(authSessionProvider);
      final location = state.matchedLocation;

      final isProtectedFeatureRoute = AuthRouteGuard.requiresProtectedSetupComplete(location);
      if (isProtectedFeatureRoute) {
        if (session.configurationStatus == StartupConfigurationStatus.valid) {
          final authTarget = AuthRouteGuard.resolveRedirect(location: location, auth: auth);
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
          final authRedirect = AuthRouteGuard.resolveRedirect(location: location, auth: auth);
          if (authRedirect != null) {
            return authRedirect;
          }

          if (auth.isAuthenticated) {
            return null;
          }

          const preAuthShellRoutes = {
            AppRoutes.startupEntry,
            AppRoutes.foundationDemo,
            AppRoutes.login,
            AppRoutes.forgotPassword,
          };
          return preAuthShellRoutes.contains(location) ? null : AppRoutes.startupEntry;
        }(),
      };

      if (startupRedirect != null) {
        return startupRedirect;
      }

      if (session.currentView == StartupCurrentView.unauthenticatedEntry) {
        final authRedirect = AuthRouteGuard.resolveRedirect(location: location, auth: auth);
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
