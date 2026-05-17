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
}
