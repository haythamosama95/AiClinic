import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/features/settings/data/role_permissions_repository.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_row.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_view.dart';
import 'package:ai_clinic/features/settings/presentation/pages/role_permissions_page.dart';
import 'package:ai_clinic/features/settings/presentation/providers/role_permissions_notifier.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/testing/auth_test_support.dart';
import '../../support/settings_rpc_test_client.dart';
import '../../support/settings_table_test_client.dart';

void main() {
  group('RolePermissionsPage', () {
    testWidgets('owner sees editable switches for matrix rows', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.owner));
      await tester.pumpAndSettle();

      expect(find.text('View only.'), findsNothing);
      expect(find.text('Manage Branches'), findsOneWidget);
      expect(find.byType(Switch), findsWidgets);
      expect(find.text('Save changes'), findsWidgets);
    });

    testWidgets('administrator sees editable switches', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.administrator));
      await tester.pumpAndSettle();

      expect(find.textContaining('View only'), findsNothing);
      expect(find.byType(Switch), findsWidgets);
    });

    testWidgets('doctor sees permission denied message', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.doctor, permissionDenied: true));
      await tester.pumpAndSettle();

      expect(find.textContaining('owners and administrators'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('toggling switch does not call RPC until save', (tester) async {
      final client = SettingsRpcTestClient();
      await tester.pumpWidget(_host(role: StaffRole.owner, rpcClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(client.rpcCalls, isEmpty);
      expect(find.text('Save changes'), findsOneWidget);
    });

    testWidgets('toggling switch does not reload auth context', (tester) async {
      _ReloadTrackingAuthNotifier.reloadCount = 0;
      await tester.pumpWidget(_host(role: StaffRole.owner));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(_ReloadTrackingAuthNotifier.reloadCount, 0);
    });

    testWidgets('dirty cell shows change indicator dot', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.owner));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.circle), findsNothing);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.circle), findsWidgets);
    });

    testWidgets('reverting toggle clears dirty state', (tester) async {
      await tester.pumpWidget(
        _host(
          role: StaffRole.owner,
          tableClient: SettingsTableTestClient({
            'roles_permissions': [
              {'role': 'owner', 'permission_key': 'ai.access', 'is_granted': false, 'is_deleted': false},
            ],
          }),
        ),
      );
      await tester.pumpAndSettle();

      final switchFinder = find.byType(Switch).first;
      final initialValue = tester.widget<Switch>(switchFinder).value;

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.circle), findsWidgets);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.circle), findsNothing);
      expect(tester.widget<Switch>(switchFinder).value, initialValue);
    });

    testWidgets('save button disabled until there are edits', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.owner));
      await tester.pumpAndSettle();

      final saveButton = tester.widget<TextButton>(
        find.ancestor(of: find.text('Save changes'), matching: find.byType(TextButton)),
      );
      expect(saveButton.onPressed, isNull);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('matrix renders full-width table with role columns', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.owner));
      await tester.pumpAndSettle();

      expect(find.byType(Table), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Administrator'), findsOneWidget);
      expect(find.text('Doctor'), findsOneWidget);
      expect(find.text('Receptionist'), findsOneWidget);
      expect(find.text('Lab staff'), findsOneWidget);
    });

    testWidgets('save changes calls update_role_permission RPC', (tester) async {
      final client = SettingsRpcTestClient();
      await tester.pumpWidget(_host(role: StaffRole.owner, rpcClient: client));
      await tester.pumpAndSettle();

      final switchFinder = find.byType(Switch).first;
      final initialValue = tester.widget<Switch>(switchFinder).value;
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save changes').first);
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'update_role_permission');
      expect(client.lastParams, containsPair('p_is_granted', !initialValue));
    });

    testWidgets('successful save shows confirmation snackbar', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.owner));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Role permissions saved'), findsOneWidget);
      expect(find.textContaining('session permissions were refreshed'), findsOneWidget);
    });

    testWidgets('advanced: RPC FORBIDDEN shows error snackbar', (tester) async {
      final client = SettingsRpcTestClient(
        rpcResults: {
          'update_role_permission': {
            'success': false,
            'error_code': 'FORBIDDEN',
            'error_message': 'Only owners and administrators may update the permission matrix.',
          },
        },
      );
      await tester.pumpWidget(_host(role: StaffRole.owner, rpcClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('owners and administrators'), findsOneWidget);
    });

    testWidgets('successful save reloads auth context', (tester) async {
      _ReloadTrackingAuthNotifier.reloadCount = 0;
      await tester.pumpWidget(_host(role: StaffRole.owner));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes').first);
      await tester.pumpAndSettle();

      expect(_ReloadTrackingAuthNotifier.reloadCount, 1);
    });

    testWidgets('category headers group permissions', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.owner));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Patients'), findsOneWidget);
    });

    testWidgets('edge case: empty matrix shows empty state', (tester) async {
      await tester.pumpWidget(
        _host(role: StaffRole.owner, tableClient: SettingsTableTestClient({'roles_permissions': []})),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('No permission rows'), findsOneWidget);
    });

    testWidgets('administrator save calls update_role_permission RPC', (tester) async {
      final client = SettingsRpcTestClient();
      await tester.pumpWidget(_host(role: StaffRole.administrator, rpcClient: client));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes').first);
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'update_role_permission');
    });

    testWidgets('back with unsaved changes prompts discard or save', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.owner));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('discard on leave reverts local edits', (tester) async {
      await tester.pumpWidget(_host(role: StaffRole.owner));
      await tester.pumpAndSettle();

      final switchFinder = find.byType(Switch).first;

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.text('Settings Home'), findsOneWidget);
    });

    testWidgets('invalid state: load error surfaces message', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _PresetAuthSessionNotifier(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(role: StaffRole.owner),
                ),
              ),
            ),
            rolePermissionsProvider.overrideWith(() => _ThrowingRolePermissionsNotifier()),
          ],
          child: _routerApp(const RolePermissionsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not load permission matrix'), findsOneWidget);
    });
  });
}

Widget _host({
  required StaffRole role,
  bool permissionDenied = false,
  SettingsRpcTestClient? rpcClient,
  SettingsTableTestClient? tableClient,
}) {
  final matrixClient =
      tableClient ??
      SettingsTableTestClient({
        'roles_permissions': [
          {'role': 'owner', 'permission_key': 'settings.manage_branches', 'is_granted': true, 'is_deleted': false},
          {
            'role': 'administrator',
            'permission_key': 'settings.manage_branches',
            'is_granted': true,
            'is_deleted': false,
          },
          {'role': 'doctor', 'permission_key': 'patients.view', 'is_granted': true, 'is_deleted': false},
          {'role': 'doctor', 'permission_key': 'settings.manage_branches', 'is_granted': false, 'is_deleted': false},
        ],
      });

  final repo = _TestRolePermissionsRepository(
    fetchClient: matrixClient,
    rpcClient: rpcClient ?? SettingsRpcTestClient(),
  );

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(role: role, permissions: {'settings.manage_branches'}),
          ),
        ),
      ),
      authNotifierProvider.overrideWith(_ReloadTrackingAuthNotifier.new),
      if (permissionDenied)
        rolePermissionsProvider.overrideWith(() => _DeniedRolePermissionsNotifier())
      else
        rolePermissionsRepositoryProvider.overrideWithValue(repo),
    ],
    child: _routerApp(const RolePermissionsPage()),
  );
}

Widget _routerApp(Widget child) {
  return MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: AppRoutes.settingsPermissions,
      routes: [
        GoRoute(
          path: AppRoutes.settings,
          builder: (context, state) => const Scaffold(body: Text('Settings Home')),
        ),
        GoRoute(path: AppRoutes.settingsPermissions, builder: (context, state) => child),
      ],
    ),
  );
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _DeniedRolePermissionsNotifier extends RolePermissionsNotifier {
  @override
  Future<RolePermissionsUiState> build() async {
    final empty = PermissionMatrixView.fromRows(const []);
    return RolePermissionsUiState(savedMatrix: empty, workingMatrix: empty, permissionDenied: true);
  }
}

class _ThrowingRolePermissionsNotifier extends RolePermissionsNotifier {
  @override
  Future<RolePermissionsUiState> build() async {
    throw StateError('network down');
  }
}

class _TestRolePermissionsRepository extends RolePermissionsRepositoryImpl {
  _TestRolePermissionsRepository({required SupabaseClient fetchClient, required SupabaseClient rpcClient})
    : _fetchClient = fetchClient,
      super(rpcClient);

  final SupabaseClient _fetchClient;

  @override
  Future<List<PermissionMatrixRow>> fetchMatrix() {
    return RolePermissionsRepositoryImpl(_fetchClient).fetchMatrix();
  }
}

class _ReloadTrackingAuthNotifier extends AuthNotifier {
  static var reloadCount = 0;

  @override
  AuthUiState build() => const AuthUiState();

  @override
  Future<void> reloadContext() async {
    reloadCount++;
  }
}
