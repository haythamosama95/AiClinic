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

  // V1-3 patient management
  static const patients = '/patients';
  static const patientsNew = '/patients/new';

  /// Patient detail: `/patients/:id`
  static String patientDetail(String patientId) => '$patients/$patientId';

  /// Patient edit: `/patients/:id/edit`
  static String patientEdit(String patientId) => '$patients/$patientId/edit';

  /// Static patient hub paths (list + register).
  static const patientStaticPaths = <String>[patients, patientsNew];

  // V1-4 appointment management
  static const appointments = '/appointments';
  static const appointmentsBook = '/appointments/book';
  static const appointmentsQueue = '/appointments/queue';
  static const appointmentsCalendar = '/appointments/calendar';

  /// Doctor schedule: `/appointments/schedule/:doctorId`
  static String appointmentsSchedule(String doctorId) => '$appointments/schedule/$doctorId';

  /// Static appointment hub paths (hub, book, queue, calendar).
  static const appointmentStaticPaths = <String>[
    appointments,
    appointmentsBook,
    appointmentsQueue,
    appointmentsCalendar,
  ];

  // V1-5 visit medical records
  static const visits = '/visits';
  static const visitDocumentSegment = 'document';
  static const visitDetailSegment = 'detail';

  /// Visit documentation: `/visits/:visitId/document`
  static String visitDocument(String visitId) => '$visits/$visitId/$visitDocumentSegment';

  /// Visit clinical detail: `/visits/:visitId/detail`
  static String visitDetail(String visitId) => '$visits/$visitId/$visitDetailSegment';
}
