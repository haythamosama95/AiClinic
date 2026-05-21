import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/auth/presentation/pages/auth_shell_page.dart';
import 'package:ai_clinic/features/auth/presentation/pages/clinic_bootstrap_page.dart';
import 'package:ai_clinic/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:ai_clinic/features/auth/presentation/pages/login_page.dart';
import 'package:ai_clinic/features/auth/presentation/pages/staff_provisioning_placeholder_page.dart';
import 'package:ai_clinic/features/foundation_demo/presentation/pages/foundation_demo_page.dart';
import 'package:ai_clinic/features/startup/presentation/pages/protected_placeholder_page.dart';
import 'package:ai_clinic/features/startup/presentation/pages/protected_route_blocked_page.dart';
import 'package:ai_clinic/features/startup/presentation/pages/setup_guidance_page.dart';
import 'package:ai_clinic/features/startup/presentation/pages/startup_check_page.dart';
import 'package:ai_clinic/features/startup/presentation/pages/startup_entry_page.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/shared/providers/startup_session_provider.dart';

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
      GoRoute(path: AppRoutes.startupCheck, builder: (context, state) => const StartupCheckPage()),
      GoRoute(path: AppRoutes.startupEntry, builder: (context, state) => const StartupEntryPage()),
      GoRoute(path: AppRoutes.setupGuidance, builder: (context, state) => const SetupGuidancePage()),
      GoRoute(path: AppRoutes.protectedBlocked, builder: (context, state) => const ProtectedRouteBlockedPage()),
      GoRoute(path: AppRoutes.protectedPlaceholder, builder: (context, state) => const ProtectedPlaceholderPage()),
      GoRoute(path: AppRoutes.foundationDemo, builder: (context, state) => const FoundationDemoPage()),
      GoRoute(path: AppRoutes.login, builder: (context, state) => const LoginPage()),
      GoRoute(path: AppRoutes.forgotPassword, builder: (context, state) => const ForgotPasswordPage()),
      GoRoute(path: AppRoutes.bootstrap, builder: (context, state) => const ClinicBootstrapPage()),
      GoRoute(
        path: AppRoutes.staffCreate,
        builder: (context, state) => const StaffProvisioningPlaceholderPage(title: 'Create staff'),
      ),
      GoRoute(
        path: AppRoutes.staffPasswordReset,
        builder: (context, state) => const StaffProvisioningPlaceholderPage(title: 'Reset staff password'),
      ),
      GoRoute(path: AppRoutes.home, builder: (context, state) => const AuthShellPage()),
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
        return AuthRouteGuard.resolveRedirect(location: location, auth: auth);
      }

      return null;
    },
  );
});
