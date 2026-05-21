/// Central route names for startup shell and auth flows.
abstract final class AppRoutes {
  static const startupEntry = '/';
  static const startupCheck = '/startup-check';
  static const setupGuidance = '/setup-guidance';
  static const protectedBlocked = '/protected-blocked';
  static const protectedPlaceholder = '/protected/dashboard';
  static const protectedPrefix = '/protected';
  static const foundationDemo = '/foundation-demo';

  // Auth (V1-1)
  static const login = '/login';
  static const bootstrap = '/bootstrap';
  static const home = '/home';
  static const forgotPassword = '/forgot-password';

  /// Minimal staff provisioning (US6); blocked while `setup_required` is true.
  static const staffCreate = '/staff/create';
  static const staffPasswordReset = '/staff/reset-password';

  /// Clinic workstation settings (authenticated, setup complete).
  static const settings = '/settings';
  static const settingsIdleTimeout = '/settings/idle-timeout';
}
