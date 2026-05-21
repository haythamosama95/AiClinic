import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

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
        location.startsWith('${AppRoutes.protectedPrefix}/');
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

        if (location == AppRoutes.home || requiresProtectedSetupComplete(location)) {
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
