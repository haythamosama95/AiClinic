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

  // V1-2 settings administration (org / branch / staff / permissions)
  static const settingsOrganization = '/settings/organization';
  static const settingsBranches = '/settings/branches';
  static const settingsBranchesNew = '/settings/branches/new';
  static const settingsStaff = '/settings/staff';
  static const settingsStaffNew = '/settings/staff/new';
  static const settingsPermissions = '/settings/permissions';

  /// Edit branch: `/settings/branches/:id/edit`
  static String settingsBranchEdit(String branchId) => '$settingsBranches/$branchId/edit';

  /// Staff detail: `/settings/staff/:id`
  static String settingsStaffDetail(String staffId) => '$settingsStaff/$staffId';

  /// Staff password reset: `/settings/staff/:id/reset-password`
  static String settingsStaffResetPassword(String staffId) => '$settingsStaff/$staffId/reset-password';

  /// All V1-2 admin settings paths (static + parameterized builders).
  static const adminSettingsPaths = <String>[
    settingsOrganization,
    settingsBranches,
    settingsBranchesNew,
    settingsStaff,
    settingsStaffNew,
    settingsPermissions,
  ];
}
