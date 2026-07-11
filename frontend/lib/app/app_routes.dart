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
  static const dashboard = '/dashboard';
  static const encounters = '/encounters';
  static const workspace = '/workspace';
  static const reports = '/reports';
  static const forgotPassword = '/forgot-password';

  /// Minimal staff provisioning (US6); blocked while `setup_required` is true.
  static const staffCreate = '/staff/create';
  static const staffPasswordReset = '/staff/reset-password';

  /// Clinic workstation settings (authenticated, setup complete).
  static const settings = '/settings';
  static const settingsGeneral = '/settings/general';
  static const settingsNotifications = '/settings/notifications';
  static const settingsIdleTimeout = '/settings/idle-timeout';

  /// Settings page screen segments (web `SETTINGS_SCREENS` ids).
  static const settingsScreenSegments = <String>['general', 'branches', 'staff', 'services', 'notifications'];

  /// Resolves the active settings screen id from a location path (web `resolveScreen`).
  static String settingsScreenFromPath(String path) {
    final segments = Uri.parse(path).pathSegments;
    if (segments.length >= 2 && segments.first == 'settings') {
      final screen = segments[1];
      if (settingsScreenSegments.contains(screen)) {
        return screen;
      }
    }
    return 'general';
  }

  /// Builds the route for a settings screen tab.
  static String settingsScreenPath(String screenId) => '$settings/$screenId';

  /// Stable shell transition key for settings routes.
  ///
  /// Tab switches and nested settings flows keep the same key so the app shell
  /// does not animate the settings nav rail; only [SettingsScreenPanel] transitions.
  static String shellPageTransitionKeyForLocation(String location) {
    final segments = Uri.parse(location).pathSegments;
    if (segments.isNotEmpty && segments.first == 'settings') {
      if (segments.length == 1) {
        return settings;
      }
      if (settingsScreenSegments.contains(segments[1])) {
        return settings;
      }
    }
    return location;
  }

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
  ///
  /// Bare `/settings/branches` and `/settings/staff` are settings page tabs;
  /// admin list/create flows use the `…/new` and parameterized routes below.
  static const adminSettingsPaths = <String>[
    settingsOrganization,
    settingsBranchesNew,
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

  /// Appointment detail: `/appointments/:appointmentId`
  static String appointmentDetail(String appointmentId) => '$appointments/$appointmentId';

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
  static String visitDocument(String visitId, {bool startEditing = false}) {
    final base = '$visits/$visitId/$visitDocumentSegment';
    return startEditing ? '$base?edit=1' : base;
  }

  /// Visit clinical detail: `/visits/:visitId/detail`
  static String visitDetail(String visitId) => '$visits/$visitId/$visitDetailSegment';

  // V1-6 billing
  static const billing = '/billing';
  static const billingInvoices = '/billing/invoices';
  static const billingInsuranceProviders = '/billing/insurance-providers';
  static const settingsBilling = '/settings/billing';

  // V1-8 service catalog (015)
  static const settingsServices = '/settings/services';
  static const settingsServicesNew = '/settings/services/new';

  /// Service editor: `/settings/services/:id/edit`
  static String settingsServiceEdit(String serviceId) => '/settings/services/$serviceId/edit';

  static const serviceCatalogStaticPaths = <String>[settingsServices, settingsServicesNew];

  /// Invoice detail: `/billing/invoices/:id`
  static String billingInvoiceDetail(String invoiceId) => '$billingInvoices/$invoiceId';

  static const billingInvoiceEditSegment = 'edit';

  /// Draft invoice editor: `/billing/invoices/:id/edit`
  static String billingInvoiceEdit(String invoiceId) => '$billingInvoices/$invoiceId/$billingInvoiceEditSegment';

  /// Static billing hub paths.
  static const billingStaticPaths = <String>[billing, billingInvoices, billingInsuranceProviders, settingsBilling];

  // V1-7 shift management
  static const shiftsCalendar = '/shifts/calendar';
  static const shiftsNew = '/shifts/new';

  /// Shift detail: `/shifts/:id`
  static String shiftDetail(String shiftId) => '$shifts/$shiftId';

  static const shifts = '/shifts';

  static const shiftStaticPaths = <String>[shiftsCalendar, shiftsNew];

  /// Static paths for each settings screen tab.
  static const settingsScreenPaths = <String>[
    settingsGeneral,
    settingsBranches,
    settingsStaff,
    settingsServices,
    settingsNotifications,
  ];

  /// All settings-related admin paths including screen tabs used by shell navigation.
  static const allSettingsAdminPaths = <String>[
    ...settingsScreenPaths,
    ...adminSettingsPaths,
    settingsIdleTimeout,
    settingsBilling,
    ...serviceCatalogStaticPaths,
  ];
}
