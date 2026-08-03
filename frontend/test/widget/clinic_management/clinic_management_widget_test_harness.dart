// Test-only harness for clinic management page widget tests.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/components/app_tabs.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/billing/domain/billing_settings.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/providers/billing_settings_notifier.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/domain/permission_matrix_row.dart';
import 'package:ai_clinic/features/clinic-management/domain/permission_matrix_view.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/branch_form_values.dart';
import 'package:ai_clinic/features/clinic-management/presentation/pages/clinic_management_page.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_management_notifier.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/role_permissions_notifier.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/working_schedule.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:ai_clinic/features/service_catalog/presentation/models/service_list_filters.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_catalog_list_notifier.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/role_permission_seed.dart';
import '../../helpers/settings_test_support.dart';

const clinicManagementTestOrgId = '20202020-2020-4020-8020-202020202020';
const clinicManagementTestBranchId = '44444444-4444-4444-8444-444444444444';
const clinicManagementTestStaffId = '22222222-2222-4222-8222-222222222222';
const clinicManagementTestAdminStaffId = '11111111-1111-4111-8111-111111111111';
const clinicManagementTestServiceId = '33333333-3333-4333-8333-333333333333';

const clinicManagementWideSurfaceSize = Size(1400, 1000);

/// Tracks [ClinicManagementNotifier.reload] invocations.
class SpyClinicManagementNotifier extends ClinicManagementNotifier {
  SpyClinicManagementNotifier(this._state);

  final ClinicManagementState _state;

  var reloadCallCount = 0;

  @override
  Future<ClinicManagementState> build() async => _state;

  @override
  Future<void> reload() async {
    reloadCallCount++;
    state = AsyncData(_state);
  }
}

/// Never completes so [clinicManagementProvider] stays in loading.
class LoadingClinicManagementNotifier extends ClinicManagementNotifier {
  @override
  Future<ClinicManagementState> build() async {
    return Completer<ClinicManagementState>().future;
  }

  @override
  Future<void> reload() async {
    // No-op: keep the provider in loading for skeleton assertions.
  }
}

/// Returns data on build, then surfaces an error on [reload] (matches page mount behavior).
class ReloadErrorClinicManagementNotifier extends ClinicManagementNotifier {
  ReloadErrorClinicManagementNotifier(this._state, this.message);

  final ClinicManagementState _state;
  final String message;

  @override
  Future<ClinicManagementState> build() async => _state;

  @override
  Future<void> reload() async {
    state = AsyncError<ClinicManagementState>(Exception(message), StackTrace.current);
  }
}

class _PresetRolePermissionsNotifier extends RolePermissionsNotifier {
  _PresetRolePermissionsNotifier(this._state);

  final RolePermissionsUiState _state;

  @override
  Future<RolePermissionsUiState> build() async => _state;
}

class _PresetServiceCatalogListNotifier extends ServiceCatalogListNotifier {
  _PresetServiceCatalogListNotifier(this._state);

  final ServiceCatalogListUiState _state;

  @override
  Future<ServiceCatalogListUiState> build() async => _state;
}

class _PresetBillingSettingsNotifier extends BillingSettingsNotifier {
  _PresetBillingSettingsNotifier(this._state);

  final BillingSettings _state;

  @override
  Future<BillingSettings> build() async => _state;
}

/// Authenticated session for clinic management widget tests.
AuthSessionState clinicManagementAuthSession({
  Set<String>? permissions,
  StaffRole role = StaffRole.administrator,
  List<String>? branchIds,
  String? activeBranchId,
}) {
  final branches = branchIds ?? [clinicManagementTestBranchId];
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: AuthSessionContext(
      staffProfile: StaffProfile(
        staffMemberId: clinicManagementTestAdminStaffId,
        fullName: 'Admin User',
        role: role,
        isBootstrapAdmin: role == StaffRole.administrator,
        isActive: true,
      ),
      organizationId: clinicManagementTestOrgId,
      branchIds: branches,
      activeBranchId: activeBranchId ?? branches.first,
      permissions: permissions ?? RolePermissionSeed.administrator,
      setupRequired: false,
    ),
  );
}

/// Default [ClinicManagementState] for widget tests.
ClinicManagementState buildClinicManagementState({
  OrganizationProfile? organization,
  List<BranchListItem>? branches,
  List<StaffListItem>? staff,
}) {
  return ClinicManagementState(
    organization: organization ??
        sampleOrganizationProfile(
          id: clinicManagementTestOrgId,
          currencyCode: 'USD',
          timezone: 'America/New_York',
        ),
    branches: branches ??
        [
          sampleBranch(
            id: clinicManagementTestBranchId,
            name: 'Main Branch',
            code: 'MAIN',
          ),
        ],
    staff: staff ??
        const [
          StaffListItem(
            id: clinicManagementTestStaffId,
            fullName: 'Jane Doe',
            role: StaffRole.doctor,
            isActive: true,
            username: 'jane',
            branches: [
              StaffBranchLabel(
                id: clinicManagementTestBranchId,
                name: 'Main Branch',
                isPrimary: true,
              ),
            ],
          ),
        ],
  );
}

ServiceCatalogListUiState buildServiceCatalogListState({
  List<ServiceListItem>? items,
  int? total,
}) {
  final resolvedItems = items ??
      [
        ServiceListItem(
          serviceId: clinicManagementTestServiceId,
          name: 'Consultation',
          defaultPrice: Money.parse('150.00'),
          globalStatus: GlobalStatus.active,
          assignedBranchCount: 1,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ];
  return ServiceCatalogListUiState(
    items: resolvedItems,
    total: total ?? resolvedItems.length,
    filters: const ServiceListFilters(),
  );
}

RolePermissionsUiState buildRolePermissionsState({bool editable = true}) {
  final matrix = PermissionMatrixView.fromRows([
    const PermissionMatrixRow(
      role: StaffRole.administrator,
      permissionKey: PermissionKeys.patientsView,
      isGranted: true,
    ),
  ]);
  return RolePermissionsUiState(
    savedMatrix: matrix,
    workingMatrix: matrix,
    editable: editable,
  );
}

List<Override> _resolveClinicManagementOverrides({
  AuthSessionState? auth,
  required List<Override> overrides,
}) {
  if (overrides.isNotEmpty) {
    return overrides;
  }
  return clinicManagementProviderOverrides(auth: auth);
}

/// Default provider bundle for clinic management page widget tests.
List<Override> clinicManagementProviderOverrides({
  AuthSessionState? auth,
  ClinicManagementState? clinicState,
  SpyClinicManagementNotifier? clinicNotifier,
  Override? clinicManagementOverride,
  ServiceCatalogListUiState? catalogState,
  BillingSettings? billingSettings,
  RolePermissionsUiState? rolePermissionsState,
  List<Override> extraOverrides = const [],
}) {
  final resolvedAuth = auth ?? clinicManagementAuthSession();
  final resolvedClinicState = clinicState ?? buildClinicManagementState();
  final resolvedCatalogState = catalogState ?? buildServiceCatalogListState();
  final resolvedBillingSettings = billingSettings ?? const BillingSettings(allowPartialPayments: false);
  final resolvedRolePermissions = rolePermissionsState ?? buildRolePermissionsState();

  return [
    authSessionProvider.overrideWith(
      () => MutableAuthSessionNotifier(resolvedAuth),
    ),
    if (clinicManagementOverride != null)
      clinicManagementOverride
    else
      clinicManagementProvider.overrideWith(
        () => clinicNotifier ?? SpyClinicManagementNotifier(resolvedClinicState),
      ),
    serviceCatalogListProvider.overrideWith(
      () => _PresetServiceCatalogListNotifier(resolvedCatalogState),
    ),
    billingSettingsProvider.overrideWith(
      () => _PresetBillingSettingsNotifier(resolvedBillingSettings),
    ),
    rolePermissionsProvider.overrideWith(
      () => _PresetRolePermissionsNotifier(resolvedRolePermissions),
    ),
    ...extraOverrides,
  ];
}

/// Pumps [ClinicManagementPage] inside the canonical widget-test shell.
Future<void> pumpClinicManagementPage(
  WidgetTester tester, {
  List<Override> overrides = const [],
  AuthSessionState? auth,
  Size surfaceSize = clinicManagementWideSurfaceSize,
  bool scrollable = true,
}) async {
  if (find.byType(MaterialApp).evaluate().isNotEmpty) {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final page = scrollable
      ? const SingleChildScrollView(child: ClinicManagementPage())
      : const ClinicManagementPage();

  await tester.pumpWidget(
    ProviderScope(
      overrides: _resolveClinicManagementOverrides(
        auth: auth,
        overrides: overrides,
      ),
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: page),
      ),
    ),
  );
}

/// Pumps one frame plus a short delay for clinic management async providers.
Future<void> pumpClinicManagementFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Waits for the clinic management page skeleton minimum duration.
Future<void> pumpClinicManagementSkeletonTimer(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
}

/// Taps a clinic management tab by [label] without matching tab body headings.
Future<void> tapClinicManagementTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppTabs),
      matching: find.text(label),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

// ---------------------------------------------------------------------------
// Legacy helpers used by component-level clinic management widget tests.
// ---------------------------------------------------------------------------

const clinicMgmtTestOrgId = clinicManagementTestOrgId;
const clinicMgmtTestBranchId = clinicManagementTestBranchId;
const clinicMgmtTestStaffId = clinicManagementTestStaffId;
const clinicMgmtWideSurface = Size(1280, 900);

const clinicMgmtSampleOrganization = OrganizationProfile(
  id: clinicMgmtTestOrgId,
  name: 'Test Clinic',
  currencyCode: 'USD',
  timezone: 'America/New_York',
);

BranchListItem clinicMgmtSampleBranch({
  String id = clinicMgmtTestBranchId,
  String name = 'Main Branch',
  String code = 'MAIN',
  bool isActive = true,
}) {
  return sampleBranch(id: id, name: name, code: code, isActive: isActive);
}

StaffListItem clinicMgmtSampleStaff({
  String id = clinicMgmtTestStaffId,
  String fullName = 'Jane Doe',
  String username = 'jane',
  StaffRole role = StaffRole.doctor,
}) {
  return StaffListItem(
    id: id,
    fullName: fullName,
    role: role,
    isActive: true,
    username: username,
    phone: '201234567890',
    branches: [
      StaffBranchLabel(id: clinicMgmtTestBranchId, name: 'Main Branch', isPrimary: true),
    ],
  );
}

BranchFormValues clinicMgmtValidBranchFormValues() {
  return BranchFormValues(
    name: 'New Branch',
    code: 'NEW',
    address: '123 Street',
    phone: '1234567890',
    mapsUrl: 'https://maps.example.com',
    workingSchedule: defaultWorkingSchedule(),
  );
}

PermissionMatrixView clinicMgmtSamplePermissionMatrix() {
  return PermissionMatrixView.fromRows(const [
    PermissionMatrixRow(role: StaffRole.administrator, permissionKey: 'patients.view', isGranted: true),
    PermissionMatrixRow(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: true),
    PermissionMatrixRow(role: StaffRole.receptionist, permissionKey: 'patients.view', isGranted: false),
    PermissionMatrixRow(role: StaffRole.labStaff, permissionKey: 'patients.view', isGranted: false),
  ]);
}

AuthSessionState clinicMgmtAdminAuth() {
  return clinicManagementAuthSession(
    permissions: {
      PermissionKeys.invoicesView,
      PermissionKeys.manageBranches,
      PermissionKeys.manageStaff,
      PermissionKeys.servicesView,
      PermissionKeys.servicesManage,
    },
  );
}

AuthSessionState clinicMgmtDoctorAuth() {
  return clinicManagementAuthSession(
    role: StaffRole.doctor,
    permissions: RolePermissionSeed.doctor,
  );
}

Future<void> pumpClinicMgmtWidget(
  WidgetTester tester, {
  required Widget child,
  List<Override> overrides = const [],
  bool scrollable = true,
  Size surfaceSize = clinicMgmtWideSurface,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: scrollable ? SingleChildScrollView(child: child) : child,
        ),
      ),
    ),
  );
}

Future<void> settleClinicMgmtWidget(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Finder clinicMgmtEditableText(String semanticsId) {
  return find.descendant(
    of: find.bySemanticsIdentifier(semanticsId),
    matching: find.byType(EditableText),
  );
}

Finder clinicMgmtSearchField(String placeholderOrAriaLabel) {
  final byAriaLabel = find.descendant(
    of: find.bySemanticsLabel(placeholderOrAriaLabel),
    matching: find.byType(EditableText),
  );
  if (byAriaLabel.evaluate().isNotEmpty) {
    return byAriaLabel;
  }

  return find.byType(EditableText).first;
}

Future<void> enterClinicMgmtSearch(
  WidgetTester tester,
  String placeholderOrAriaLabel,
  String value,
) async {
  final field = clinicMgmtSearchField(placeholderOrAriaLabel);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pump();
  await tester.enterText(field, value);
}

class PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class PresetBillingSettingsNotifier extends BillingSettingsNotifier {
  PresetBillingSettingsNotifier(this._settings);

  final BillingSettings _settings;

  @override
  Future<BillingSettings> build() async => _settings;
}

class LoadingBillingSettingsNotifier extends BillingSettingsNotifier {
  @override
  Future<BillingSettings> build() async {
    await Completer<void>().future;
    return const BillingSettings(allowPartialPayments: false);
  }
}

class ErrorBillingSettingsNotifier extends BillingSettingsNotifier {
  @override
  Future<BillingSettings> build() async {
    throw StateError('Billing settings unavailable');
  }
}

class LoadingRolePermissionsNotifier extends RolePermissionsNotifier {
  @override
  Future<RolePermissionsUiState> build() async {
    await Completer<void>().future;
    return RolePermissionsUiState(
      savedMatrix: PermissionMatrixView.empty,
      workingMatrix: PermissionMatrixView.empty,
    );
  }
}

class PresetRolePermissionsNotifier extends RolePermissionsNotifier {
  PresetRolePermissionsNotifier(this._state);

  final RolePermissionsUiState _state;

  @override
  Future<RolePermissionsUiState> build() async => _state;
}
