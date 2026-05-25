import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/data/organization_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/pump_auth_app.dart';
import '../../support/settings_table_test_client.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:ai_clinic/testing/startup_test_support.dart';

/// Simulated tenant created by V1-1 bootstrap (spec test case 12).
const _bootstrapOrgId = '00000000-0000-4000-8000-000000000020';
const _bootstrapOrgName = 'Sunrise Dental Clinic';
const _bootstrapBranchId = '00000000-0000-4000-8000-000000000001';
const _bootstrapBranchName = 'Main Clinic';
const _bootstrapStaffId = '00000000-0000-4000-8000-000000000010';
const _bootstrapStaffName = 'Clinic Bootstrap Admin';

Map<String, List<Map<String, dynamic>>> _bootstrapTenantTables() => {
  'organizations': [
    {
      'id': _bootstrapOrgId,
      'name': _bootstrapOrgName,
      'logo_url': null,
      'currency_code': 'EGP',
      'timezone': 'Africa/Cairo',
      'settings_json': {},
      'subscription_tier': 'standard',
      'subscription_valid_until': null,
      'is_deleted': false,
    },
  ],
  'branches': [
    {
      'id': _bootstrapBranchId,
      'name': _bootstrapBranchName,
      'code': 'MAIN',
      'is_active': true,
      'is_deleted': false,
      'organization_id': _bootstrapOrgId,
    },
  ],
  'staff_members': [
    {
      'id': _bootstrapStaffId,
      'full_name': _bootstrapStaffName,
      'role': 'owner',
      'phone': null,
      'is_active': true,
      'is_deleted': false,
    },
  ],
  'staff_branch_assignments': [
    {'staff_member_id': _bootstrapStaffId, 'branch_id': _bootstrapBranchId, 'is_primary': true, 'is_deleted': false},
  ],
};

void main() {
  group('bootstrap data in steady-state settings (US6)', () {
    testWidgets('trivial: bootstrap organization name appears in organization settings', (tester) async {
      await _pumpOwnerWithBootstrapData(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.settingsOrganization);
      await tester.pumpAndSettle();

      expect(find.text(_bootstrapOrgName), findsOneWidget);
      expect(find.text('EGP'), findsOneWidget);
    });

    testWidgets('trivial: bootstrap branch appears in branch list', (tester) async {
      await _pumpOwnerWithBootstrapData(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.settingsBranches);
      await tester.pumpAndSettle();

      expect(find.text(_bootstrapBranchName), findsOneWidget);
      expect(find.textContaining('Code: MAIN'), findsOneWidget);
    });

    testWidgets('trivial: bootstrap staff appears in staff list', (tester) async {
      await _pumpOwnerWithBootstrapData(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.settingsStaff);
      await tester.pumpAndSettle();

      expect(find.text(_bootstrapStaffName), findsOneWidget);
    });

    testWidgets('advanced: legacy staff create redirects to settings staff form', (tester) async {
      await _pumpOwnerWithBootstrapData(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.staffCreate);
      await tester.pumpAndSettle();

      expect(
        container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path,
        AppRoutes.settingsStaffNew,
      );
      expect(find.text('Create staff account'), findsOneWidget);
    });

    testWidgets('advanced: legacy password reset redirects to settings staff list', (tester) async {
      await _pumpOwnerWithBootstrapData(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.staffPasswordReset);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.settingsStaff);
      expect(find.text('New staff'), findsOneWidget);
    });

    testWidgets('stupid usage: doctor without manage_staff lands on settings hub from legacy create', (tester) async {
      await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(_DoctorSessionNotifier.new)]);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _DoctorSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.staffCreate);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.settings);
    });

    testWidgets('edge case: setup_required keeps bootstrap route and blocks legacy staff create redirect', (
      tester,
    ) async {
      await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(_OwnerSessionNotifier.new)]);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _OwnerSessionNotifier).setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            setupRequired: true,
            permissions: {'settings.manage_staff', 'settings.manage_branches'},
          ),
        ),
      );
      container.read(appRouterProvider).go(AppRoutes.staffCreate);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.bootstrap);
    });

    testWidgets('edge case: setup complete bootstrap route redirects to home', (tester) async {
      await _pumpOwnerWithBootstrapData(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.bootstrap);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.home);
    });

    testWidgets('invalid state: empty tenant tables show empty staff list', (tester) async {
      final tableClient = SettingsTableTestClient({
        'organizations': [
          {
            'id': _bootstrapOrgId,
            'name': _bootstrapOrgName,
            'logo_url': null,
            'currency_code': 'EGP',
            'timezone': 'Africa/Cairo',
            'settings_json': {},
            'subscription_tier': 'standard',
            'subscription_valid_until': null,
            'is_deleted': false,
          },
        ],
        'branches': [],
        'staff_members': [],
      });

      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(_OwnerSessionNotifier.new),
          staffAdminRepositoryProvider.overrideWithValue(StaffAdminRepositoryImpl(tableClient)),
          branchRepositoryProvider.overrideWithValue(BranchRepositoryImpl(tableClient)),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _OwnerSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.settingsStaff);
      await tester.pumpAndSettle();

      expect(find.text('No active staff members.'), findsOneWidget);
      expect(find.text(_bootstrapStaffName), findsNothing);
    });

    testWidgets('regression: settings hub still reachable after bootstrap migration', (tester) async {
      await _pumpOwnerWithBootstrapData(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.settings);
      await tester.pumpAndSettle();

      expect(find.text('Clinic administration'), findsOneWidget);
      expect(find.text('Organization'), findsOneWidget);
    });

    testWidgets('regression: home shell links to settings staff instead of legacy create', (tester) async {
      await _pumpOwnerWithBootstrapData(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.home);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Settings'), findsOneWidget);
      expect(find.text('Manage staff'), findsOneWidget);
      expect(find.text('Create staff account'), findsNothing);

      await tester.scrollUntilVisible(find.text('Manage staff'), 80);
      await tester.tap(find.text('Manage staff'));
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.settingsStaff);
    });
  });

  group('AuthRouteGuard steadyStateProvisioningRedirect', () {
    test('owner with setup complete redirects legacy staff create to settings form', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(permissions: {'settings.manage_staff'}),
      );

      expect(
        AuthRouteGuard.steadyStateProvisioningRedirect(location: AppRoutes.staffCreate, auth: auth),
        AppRoutes.settingsStaffNew,
      );
    });

    test('setup_required does not redirect legacy routes', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(setupRequired: true, permissions: {'settings.manage_staff'}),
      );

      expect(AuthRouteGuard.steadyStateProvisioningRedirect(location: AppRoutes.staffCreate, auth: auth), isNull);
    });
  });
}

Future<void> _pumpOwnerWithBootstrapData(WidgetTester tester) async {
  final tableClient = SettingsTableTestClient(_bootstrapTenantTables());
  await pumpAuthApp(
    tester,
    extraOverrides: [
      authSessionProvider.overrideWith(_OwnerSessionNotifier.new),
      organizationRepositoryProvider.overrideWithValue(_BootstrapOrganizationRepository(tableClient)),
      branchRepositoryProvider.overrideWithValue(BranchRepositoryImpl(tableClient)),
      staffAdminRepositoryProvider.overrideWithValue(StaffAdminRepositoryImpl(tableClient)),
    ],
  );
  await completeStartupBootstrap(tester);

  final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  (container.read(authSessionProvider.notifier) as _OwnerSessionNotifier).setAuthenticated();
}

class _BootstrapOrganizationRepository extends OrganizationRepositoryImpl {
  _BootstrapOrganizationRepository(this._fetchClient) : super(_fetchClient);

  final SupabaseClient _fetchClient;

  @override
  Future<OrganizationProfile?> fetchProfile({required String organizationId}) {
    return OrganizationRepositoryImpl(_fetchClient).fetchProfile(organizationId: organizationId);
  }
}

class _DoctorSessionNotifier extends TestAuthSessionNotifier {
  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(role: StaffRole.doctor, permissions: {'patients.view'}),
      ),
    );
  }
}

class _OwnerSessionNotifier extends TestAuthSessionNotifier {
  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(permissions: {'settings.manage_branches', 'settings.manage_staff'}),
      ),
    );
  }
}
