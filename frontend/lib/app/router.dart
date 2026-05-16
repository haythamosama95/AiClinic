import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/startup/presentation/pages/protected_placeholder_page.dart';
import '../features/startup/presentation/pages/protected_route_blocked_page.dart';
import '../features/startup/presentation/pages/setup_guidance_page.dart';
import '../features/startup/presentation/pages/startup_check_page.dart';
import '../features/startup/presentation/pages/startup_entry_page.dart';
import '../shared/providers/startup_session_provider.dart';
import 'app_routes.dart';

/// Rebuilds router redirects whenever startup session state changes.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshSignal = ValueNotifier<int>(0);
  ref.onDispose(refreshSignal.dispose);
  ref.listen<StartupSessionState>(startupSessionProvider, (_, _) {
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
    ],
    redirect: (context, state) {
      final session = ref.read(startupSessionProvider);
      final location = state.matchedLocation;

      final isProtectedFeatureRoute = location.startsWith('${AppRoutes.protectedPrefix}/');
      if (isProtectedFeatureRoute) {
        if (session.currentView != StartupCurrentView.protectedRouteBlocked) {
          notifier.blockProtectedRoute(location);
        }
        return AppRoutes.protectedBlocked;
      }

      return switch (session.currentView) {
        StartupCurrentView.startupCheck => location == AppRoutes.startupCheck ? null : AppRoutes.startupCheck,
        StartupCurrentView.setupGuidance => location == AppRoutes.setupGuidance ? null : AppRoutes.setupGuidance,
        StartupCurrentView.protectedRouteBlocked =>
          location == AppRoutes.protectedBlocked ? null : AppRoutes.protectedBlocked,
        StartupCurrentView.unauthenticatedEntry => location == AppRoutes.startupEntry ? null : AppRoutes.startupEntry,
      };
    },
  );
});
