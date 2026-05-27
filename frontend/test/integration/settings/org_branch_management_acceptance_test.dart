// Acceptance outline for spec.md test cases 1–13 (V1-2 org/branch management).
//
// Backend-only cases (2, 11) are documented here and enforced in
// `backend/tests/org_branch_management_*.sql` and `bootstrap_rpc.sql`.

import 'dart:io';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/auth/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/data/organization_repository.dart';
import 'package:ai_clinic/features/settings/data/role_permissions_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_row.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/pump_auth_app.dart';
import '../../support/settings_rpc_test_client.dart';
import '../../support/settings_table_test_client.dart';
import '../../helpers/auth_test_support.dart';
import '../../helpers/startup_test_support.dart';

/// Repository root when tests run with `cd frontend` (flutter test default).
const _repoRoot = '..';
const _orgId = '00000000-0000-4000-8000-000000000020';
const _branchMainId = '00000000-0000-4000-8000-000000000001';
const _branchSecondId = '00000000-0000-4000-8000-000000000002';
const _staffOwnerId = '00000000-0000-4000-8000-000000000010';

Map<String, List<Map<String, dynamic>>> _steadyStateTenant({
  bool secondBranchActive = true,
  bool includeInactiveBranch = false,
}) {
  final branches = <Map<String, dynamic>>[
    {
      'id': _branchMainId,
      'name': 'Main Clinic',
      'code': 'MAIN',
      'is_active': true,
      'is_deleted': false,
      'organization_id': _orgId,
    },
    if (secondBranchActive)
      {
        'id': _branchSecondId,
        'name': 'Uptown',
        'code': 'UPT',
        'is_active': true,
        'is_deleted': false,
        'organization_id': _orgId,
      },
    if (includeInactiveBranch)
      {
        'id': '00000000-0000-4000-8000-000000000003',
        'name': 'Closed Wing',
        'code': 'CLOSED',
        'is_active': false,
        'is_deleted': false,
        'organization_id': _orgId,
      },
  ];

  return {
    'organizations': [
      {
        'id': _orgId,
        'name': 'Sunrise Dental Clinic',
        'logo_url': null,
        'currency_code': 'EGP',
        'timezone': 'Africa/Cairo',
        'settings_json': {},
        'subscription_tier': 'standard',
        'subscription_valid_until': null,
        'is_deleted': false,
      },
    ],
    'branches': branches,
    'staff_members': [
      {
        'id': _staffOwnerId,
        'full_name': 'Clinic Owner',
        'role': 'owner',
        'phone': null,
        'is_active': true,
        'is_deleted': false,
      },
      {
        'id': '00000000-0000-4000-8000-000000000011',
        'full_name': 'Front Desk',
        'role': 'receptionist',
        'phone': null,
        'is_active': true,
        'is_deleted': false,
      },
    ],
    'staff_branch_assignments': [
      {'staff_member_id': _staffOwnerId, 'branch_id': _branchMainId, 'is_primary': true, 'is_deleted': false},
      {
        'staff_member_id': '00000000-0000-4000-8000-000000000011',
        'branch_id': _branchMainId,
        'is_primary': true,
        'is_deleted': false,
      },
      {
        'staff_member_id': '00000000-0000-4000-8000-000000000011',
        'branch_id': _branchSecondId,
        'is_primary': false,
        'is_deleted': false,
      },
    ],
    'roles_permissions': [
      {'role': 'owner', 'permission_key': 'settings.manage_branches', 'is_granted': true, 'is_deleted': false},
      {'role': 'administrator', 'permission_key': 'settings.manage_branches', 'is_granted': true, 'is_deleted': false},
      {'role': 'doctor', 'permission_key': 'patients.view', 'is_granted': true, 'is_deleted': false},
    ],
  };
}

void main() {
  group('spec test case 1 — organization settings', () {
    testWidgets('trivial: owner opens organization settings and sees profile', (tester) async {
      await _pumpWithTenant(tester, role: StaffRole.owner);
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.settingsOrganization);
      await tester.pumpAndSettle();

      expect(find.text('Sunrise Dental Clinic'), findsOneWidget);
      expect(find.text('Save organization settings'), findsOneWidget);
    });

    testWidgets('invalid state: doctor is redirected away from organization settings', (tester) async {
      await _pumpWithTenant(tester, role: StaffRole.doctor, permissions: {'patients.view'});
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.settingsOrganization);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.settings);
    });

    test('regression: AuthRouteGuard denies organization route for doctor', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(role: StaffRole.doctor),
      );
      expect(AuthRouteGuard.canAccessOrganizationSettings(auth), isFalse);
      expect(
        AuthRouteGuard.adminSettingsRedirect(location: AppRoutes.settingsOrganization, auth: auth),
        AppRoutes.settings,
      );
    });
  });

  group('spec test case 2 — single organization', () {
    test('backend: second organization creation is rejected (ORG_ALREADY_EXISTS)', () {
      // Enforced in backend/tests/bootstrap_rpc.sql — documented for acceptance traceability.
      final bootstrapSql = File('$_repoRoot/backend/tests/bootstrap_rpc.sql');
      expect(bootstrapSql.existsSync(), isTrue);
      expect(bootstrapSql.readAsStringSync(), contains('ORG_ALREADY_EXISTS'));
    });
  });

  group('spec test case 3 — branch lifecycle', () {
    testWidgets('trivial: active branch list shows main branch', (tester) async {
      await _pumpWithTenant(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.settingsBranches);
      await tester.pumpAndSettle();

      expect(find.text('Main Clinic'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsWidgets);

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('Deactivate'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('advanced: inactive filter hides active branches', (tester) async {
      await _pumpWithTenant(tester, tables: _steadyStateTenant(includeInactiveBranch: true));
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.settingsBranches);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inactive'));
      await tester.pumpAndSettle();

      expect(find.text('Closed Wing'), findsOneWidget);
      expect(find.text('Main Clinic'), findsNothing);

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('Reactivate'), findsOneWidget);
    });

    testWidgets('stupid usage: doctor without manage_branches cannot open branch admin', (tester) async {
      await _pumpWithTenant(tester, role: StaffRole.doctor, permissions: {'patients.view'});
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.settingsBranches);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.settings);
    });
  });

  group('spec test case 4 — last active branch block', () {
    testWidgets('edge case: LAST_ACTIVE_BRANCH shows edit shortcut', (tester) async {
      final rpcClient = SettingsRpcTestClient(
        rpcResults: {
          'set_branch_active': {
            'success': false,
            'error_code': 'LAST_ACTIVE_BRANCH',
            'error_message': 'Cannot deactivate the last active branch.',
          },
        },
      );
      await _pumpWithTenant(tester, tables: _steadyStateTenant(secondBranchActive: false), rpcClient: rpcClient);
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.settingsBranches);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();

      expect(find.text('Cannot deactivate branch'), findsOneWidget);
      expect(find.text('Edit branch'), findsOneWidget);
    });
  });

  group('spec test case 5 — multi-branch staff switcher', () {
    testWidgets('trivial: receptionist with two branches can switch in status bar', (tester) async {
      const branchA = BranchSummary(id: _branchMainId, name: 'Main Clinic');
      const branchB = BranchSummary(id: _branchSecondId, name: 'Uptown');

      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(_ReceptionistSessionNotifier.new),
          staffAssignableBranchesProvider.overrideWith((ref) async => [branchA, branchB]),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      final session = container.read(authSessionProvider.notifier) as _ReceptionistSessionNotifier;
      session.setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.home);
      await tester.pumpAndSettle();

      expect(session.state.context?.activeBranchId, _branchMainId);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uptown').last);
      await tester.pumpAndSettle();

      expect(session.state.context?.activeBranchId, _branchSecondId);
    });
  });

  group('spec test case 6 — staff deactivate lifecycle', () {
    testWidgets('advanced: deactivate staff via list menu calls set_staff_active RPC', (tester) async {
      final rpcClient = SettingsRpcTestClient();
      await _pumpWithTenant(tester, rpcClient: rpcClient);
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.settingsStaff);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();

      expect(
        rpcClient.rpcCalls.any((c) => c.function == 'set_staff_active' && c.params?['p_is_active'] == false),
        isTrue,
      );
    });

    testWidgets('regression: inactive staff hidden from active filter', (tester) async {
      final tables = _steadyStateTenant();
      tables['staff_members']![1]['is_active'] = false;
      await _pumpWithTenant(tester, tables: tables);
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.settingsStaff);
      await tester.pumpAndSettle();

      expect(find.text('Front Desk'), findsNothing);
      expect(find.text('Clinic Owner'), findsOneWidget);

      await tester.tap(find.text('Inactive'));
      await tester.pumpAndSettle();
      expect(find.text('Front Desk'), findsOneWidget);
      expect(find.text('Clinic Owner'), findsNothing);
    });
  });

  group('spec test case 7 — owner creation guard', () {
    test('edge case: administrator cannot select owner when owner already exists', () {
      final caller = sampleAuthSessionContext(role: StaffRole.administrator).staffProfile;
      final roles = ProvisioningRules.selectableRoles(caller, ownerAlreadyExists: true);
      expect(roles, isNot(contains(StaffRole.owner)));
    });

    test('regression: owner may still select owner role when owner exists', () {
      final caller = sampleAuthSessionContext(role: StaffRole.owner).staffProfile;
      final roles = ProvisioningRules.selectableRoles(caller, ownerAlreadyExists: true);
      expect(roles, contains(StaffRole.owner));
    });
  });

  group('spec test case 8 — permission revoke blocks branch admin', () {
    test('advanced: administrator without manage_branches fails branch route guard', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(role: StaffRole.administrator, permissions: {'settings.manage_staff'}),
      );
      expect(AuthRouteGuard.canAccessBranchManagement(auth), isFalse);
      expect(
        AuthRouteGuard.adminSettingsRedirect(location: AppRoutes.settingsBranches, auth: auth),
        AppRoutes.settings,
      );
    });
  });

  group('spec test case 9 — permission matrix reload', () {
    testWidgets('regression: owner remains on permissions page after reloadContext', (tester) async {
      final matrixClient = SettingsTableTestClient(_steadyStateTenant());
      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(_OwnerReloadSessionNotifier.new),
          rolePermissionsRepositoryProvider.overrideWithValue(
            _IntegrationRolePermissionsRepository(fetchClient: matrixClient, rpcClient: SettingsRpcTestClient()),
          ),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      final notifier = container.read(authSessionProvider.notifier) as _OwnerReloadSessionNotifier;
      notifier.setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.settingsPermissions);
      await tester.pumpAndSettle();

      await notifier.reloadContext();
      await tester.pumpAndSettle();

      expect(find.text('Role permissions'), findsOneWidget);
      expect(container.read(authSessionProvider).status, AuthSessionStatus.authenticated);
    });
  });

  group('spec test case 10 — administrator permission matrix', () {
    testWidgets('trivial: administrator can open read-only matrix view', (tester) async {
      final matrixClient = SettingsTableTestClient(_steadyStateTenant());
      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(_AdministratorSessionNotifier.new),
          rolePermissionsRepositoryProvider.overrideWithValue(
            _IntegrationRolePermissionsRepository(fetchClient: matrixClient, rpcClient: SettingsRpcTestClient()),
          ),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _AdministratorSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.settingsPermissions);
      await tester.pumpAndSettle();

      expect(find.text('Role permissions'), findsOneWidget);
      expect(find.text('Manage Branches'), findsOneWidget);
    });
  });

  group('spec test case 11 — backend CRUD and RLS', () {
    test('backend suite paths exist for org/branch management verification', () {
      expect(File('$_repoRoot/backend/tests/run_org_branch_management_tests.sh').existsSync(), isTrue);
      expect(File('$_repoRoot/backend/tests/org_branch_management_crud.sql').existsSync(), isTrue);
      expect(File('$_repoRoot/backend/tests/org_branch_management_rls.sql').existsSync(), isTrue);
    });
  });

  group('spec test case 12 — bootstrap data visible', () {
    testWidgets('trivial: bootstrap organization visible in settings lists', (tester) async {
      await _pumpWithTenant(tester, role: StaffRole.owner);
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.settings);
      await tester.pumpAndSettle();

      expect(find.text('Clinic administration'), findsOneWidget);
      expect(find.text('Organization'), findsOneWidget);
      expect(find.text('Branches'), findsOneWidget);
      expect(find.text('Staff'), findsOneWidget);
    });
  });

  group('spec test case 13 — inactive-only branch assignment', () {
    testWidgets('edge case: empty branch scope shows blocked shell', (tester) async {
      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(_NoBranchSessionNotifier.new),
          staffAssignableBranchesProvider.overrideWith((ref) async => []),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _NoBranchSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.home);
      await tester.pumpAndSettle();

      expect(find.text('No branch assigned'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.text('Permission demo'), findsNothing);
    });
  });

  group('FR-018a — no soft-delete UI (automated smoke)', () {
    testWidgets('branches and staff lists expose deactivate/reactivate only', (tester) async {
      await _pumpWithTenant(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

      container.read(appRouterProvider).go(AppRoutes.settingsBranches);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuButton<String>), findsWidgets);
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('Deactivate'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);

      container.read(appRouterProvider).go(AppRoutes.settingsStaff);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('Deactivate'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
    });
  });

  group('V1-1 regression smoke (phase 9 T056)', () {
    testWidgets('setup_required keeps bootstrap route over settings staff', (tester) async {
      await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(_OwnerSessionNotifier.new)]);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _OwnerSessionNotifier).setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(setupRequired: true, permissions: RolePermissionSeed.owner),
        ),
      );
      container.read(appRouterProvider).go(AppRoutes.settingsStaff);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.bootstrap);
    });

    test('regression: steady-state provisioning redirect still maps legacy staff create', () {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(permissions: {'settings.manage_staff'}),
      );
      expect(
        AuthRouteGuard.steadyStateProvisioningRedirect(location: AppRoutes.staffCreate, auth: auth),
        AppRoutes.settingsStaffNew,
      );
    });
  });
}

Future<void> _pumpWithTenant(
  WidgetTester tester, {
  StaffRole role = StaffRole.owner,
  Set<String>? permissions,
  Map<String, List<Map<String, dynamic>>>? tables,
  SettingsRpcTestClient? rpcClient,
}) async {
  final tableClient = SettingsTableTestClient(tables ?? _steadyStateTenant());
  final rpc = rpcClient ?? SettingsRpcTestClient();
  final branchRpc = BranchRepositoryImpl(rpc);
  await pumpAuthApp(
    tester,
    extraOverrides: [
      authSessionProvider.overrideWith(_ConfigurableSessionNotifier.new),
      organizationRepositoryProvider.overrideWithValue(_AcceptanceOrganizationRepository(tableClient)),
      branchRepositoryProvider.overrideWithValue(_TableBranchRepository(tableClient, branchRpc)),
      staffAdminRepositoryProvider.overrideWithValue(_TableStaffRepository(tableClient, StaffAdminRepositoryImpl(rpc))),
      rolePermissionsRepositoryProvider.overrideWithValue(
        _IntegrationRolePermissionsRepository(fetchClient: tableClient, rpcClient: rpc),
      ),
    ],
  );
  await completeStartupBootstrap(tester);

  final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  final notifier = container.read(authSessionProvider.notifier) as _ConfigurableSessionNotifier;
  notifier.configure(role: role, permissions: permissions ?? RolePermissionSeed.owner);
  notifier.setAuthenticated();
}

class _AcceptanceOrganizationRepository extends OrganizationRepositoryImpl {
  _AcceptanceOrganizationRepository(this._fetch) : super(_fetch);

  final SupabaseClient _fetch;

  @override
  Future<OrganizationProfile?> fetchProfile({required String organizationId}) {
    return OrganizationRepositoryImpl(_fetch).fetchProfile(organizationId: organizationId);
  }
}

class _TableBranchRepository extends BranchRepositoryImpl {
  _TableBranchRepository(this._tableClient, this._rpcRepo) : super(_tableClient);

  final SettingsTableTestClient _tableClient;
  final BranchRepositoryImpl _rpcRepo;

  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) {
    return BranchRepositoryImpl(_tableClient).listBranches(organizationId: organizationId, filter: filter);
  }

  @override
  Future<RpcResult> setBranchActive({required String branchId, required bool isActive}) {
    return _rpcRepo.setBranchActive(branchId: branchId, isActive: isActive);
  }
}

class _TableStaffRepository extends StaffAdminRepositoryImpl {
  _TableStaffRepository(this._tableClient, this._rpcRepo) : super(_tableClient);

  final SettingsTableTestClient _tableClient;
  final StaffAdminRepositoryImpl _rpcRepo;

  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) {
    return StaffAdminRepositoryImpl(_tableClient).listStaff(filter: filter);
  }

  @override
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) {
    return _rpcRepo.setStaffActive(staffMemberId: staffMemberId, isActive: isActive);
  }
}

class _IntegrationRolePermissionsRepository extends RolePermissionsRepositoryImpl {
  _IntegrationRolePermissionsRepository({required SupabaseClient fetchClient, required SupabaseClient rpcClient})
    : _fetchClient = fetchClient,
      super(rpcClient);

  final SupabaseClient _fetchClient;

  @override
  Future<List<PermissionMatrixRow>> fetchMatrix() {
    return RolePermissionsRepositoryImpl(_fetchClient).fetchMatrix();
  }
}

class _ConfigurableSessionNotifier extends TestAuthSessionNotifier {
  StaffRole _role = StaffRole.owner;
  Set<String> _permissions = RolePermissionSeed.owner;

  void configure({required StaffRole role, required Set<String> permissions}) {
    _role = role;
    _permissions = permissions;
  }

  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          role: _role,
          permissions: _permissions,
          branchIds: const [_branchMainId, _branchSecondId],
          activeBranchId: _branchMainId,
        ),
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
        context: sampleAuthSessionContext(permissions: RolePermissionSeed.owner),
      ),
    );
  }
}

class _OwnerReloadSessionNotifier extends TestAuthSessionNotifier {
  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(role: StaffRole.owner, permissions: RolePermissionSeed.owner),
      ),
    );
  }

  @override
  Future<void> reloadContext() async {
    final context = state.context;
    if (context == null) {
      return;
    }
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: context.copyWith(permissions: {...context.permissions, 'analytics.view'}),
      ),
    );
  }
}

class _AdministratorSessionNotifier extends TestAuthSessionNotifier {
  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          role: StaffRole.administrator,
          permissions: {'settings.manage_staff', 'settings.manage_branches'},
        ),
      ),
    );
  }
}

class _ReceptionistSessionNotifier extends TestAuthSessionNotifier {
  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          role: StaffRole.receptionist,
          branchIds: const [_branchMainId, _branchSecondId],
          activeBranchId: _branchMainId,
          permissions: RolePermissionSeed.receptionist,
        ),
      ),
    );
  }
}

class _NoBranchSessionNotifier extends TestAuthSessionNotifier {
  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(branchIds: [], permissions: RolePermissionSeed.doctor),
      ),
    );
  }
}
