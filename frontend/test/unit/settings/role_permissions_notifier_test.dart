import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/presentation/providers/role_permissions_notifier.dart';
import 'package:ai_clinic/features/settings/data/role_permissions_repository.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/settings_rpc_test_client.dart';
import '../../support/settings_table_test_client.dart';
import '../../support/fake_postgrest_rpc.dart';

class _RolePermissionsTestClient extends SettingsRpcTestClient {
  _RolePermissionsTestClient(this._tables);

  final Map<String, List<Map<String, dynamic>>> _tables;

  @override
  SupabaseQueryBuilder from(String table) => SettingsTableTestClient(_tables).from(table);
}

void main() {
  group('RolePermissionsNotifier', () {
    final matrixTables = {
      'roles_permissions': [
        {'role': 'administrator', 'permission_key': 'patients.view', 'is_granted': true, 'is_deleted': false},
        {'role': 'doctor', 'permission_key': 'patients.view', 'is_granted': true, 'is_deleted': false},
        {
          'role': 'administrator',
          'permission_key': 'settings.manage_branches',
          'is_granted': true,
          'is_deleted': false,
        },
        {'role': 'doctor', 'permission_key': 'settings.manage_branches', 'is_granted': false, 'is_deleted': false},
      ],
    };

    ProviderContainer container({StaffRole role = StaffRole.administrator, _RolePermissionsTestClient? rpcClient}) {
      final client = rpcClient ?? _RolePermissionsTestClient(matrixTables);

      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(role: role),
              ),
            ),
          ),
          rolePermissionsRepositoryProvider.overrideWithValue(RolePermissionsRepositoryImpl(client)),
        ],
      );
    }

    test('doctor build returns permissionDenied state', () async {
      final c = container(role: StaffRole.doctor);
      addTearDown(c.dispose);

      final state = await c.read(rolePermissionsProvider.future);
      expect(state.permissionDenied, isTrue);
      expect(state.editable, isFalse);
    });

    test('administrator build loads editable matrix', () async {
      final c = container();
      addTearDown(c.dispose);

      final state = await c.read(rolePermissionsProvider.future);
      expect(state.permissionDenied, isFalse);
      expect(state.editable, isTrue);
      expect(state.matrix.permissionKeys, contains('patients.view'));
    });

    test('setLocalGrant toggles working matrix without RPC', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(rolePermissionsProvider.future);
      c
          .read(rolePermissionsProvider.notifier)
          .setLocalGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false);

      final state = c.read(rolePermissionsProvider).value!;
      expect(state.hasUnsavedChanges, isTrue);
      expect(state.workingMatrix.isGranted(StaffRole.doctor, 'patients.view'), isFalse);
      expect(state.savedMatrix.isGranted(StaffRole.doctor, 'patients.view'), isTrue);
    });

    test('stupid usage: rapid toggle same cell keeps stable dirty state', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(rolePermissionsProvider.future);
      final notifier = c.read(rolePermissionsProvider.notifier);

      for (var i = 0; i < 12; i++) {
        final granted = i.isEven;
        notifier.setLocalGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: granted);
      }

      final state = c.read(rolePermissionsProvider).value!;
      expect(state.workingMatrix.isGranted(StaffRole.doctor, 'patients.view'), isFalse);
      expect(state.hasUnsavedChanges, isTrue);
    });

    test('discardChanges restores saved matrix', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(rolePermissionsProvider.future);
      final notifier = c.read(rolePermissionsProvider.notifier);
      notifier.setLocalGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false);
      notifier.discardChanges();

      final state = c.read(rolePermissionsProvider).value!;
      expect(state.hasUnsavedChanges, isFalse);
      expect(state.workingMatrix, state.savedMatrix);
    });

    test('saveChanges submits only dirty cells', () async {
      final rpcClient = _RolePermissionsTestClient(matrixTables);
      final c = container(rpcClient: rpcClient);
      addTearDown(c.dispose);

      await c.read(rolePermissionsProvider.future);
      final notifier = c.read(rolePermissionsProvider.notifier);
      notifier.setLocalGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false);

      final saved = await notifier.saveChanges();
      expect(saved, isTrue);
      expect(rpcClient.rpcCalls, hasLength(1));
      expect(rpcClient.rpcCalls.single.function, 'update_role_permissions');
      expect(rpcClient.rpcCalls.single.params, containsPair('p_changes', isA<List<dynamic>>()));
    });

    test('saveChanges no-op when matrix unchanged', () async {
      final rpcClient = _RolePermissionsTestClient(matrixTables);
      final c = container(rpcClient: rpcClient);
      addTearDown(c.dispose);

      await c.read(rolePermissionsProvider.future);
      final saved = await c.read(rolePermissionsProvider.notifier).saveChanges();

      expect(saved, isTrue);
      expect(rpcClient.rpcCalls, isEmpty);
    });

    test('saveChanges refetches matrix on partial RPC failure', () async {
      final rpcClient = _PartialFailureRpcClient(matrixTables);
      final c = container(rpcClient: rpcClient);
      addTearDown(c.dispose);

      await c.read(rolePermissionsProvider.future);
      final notifier = c.read(rolePermissionsProvider.notifier);
      notifier
        ..setLocalGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false)
        ..setLocalGrant(role: StaffRole.doctor, permissionKey: 'settings.manage_branches', isGranted: true);

      final saved = await notifier.saveChanges();
      expect(saved, isFalse);

      final state = c.read(rolePermissionsProvider).value!;
      expect(state.isSaving, isFalse);
      expect(state.errorMessage, isNotNull);
      expect(state.workingMatrix, state.savedMatrix);
      expect(state.hasUnsavedChanges, isFalse);
    });

    test('saveChanges surfaces PERMISSION_NOT_DELEGABLE for billing.manage', () async {
      final tables = {
        'roles_permissions': [
          {
            'role': 'administrator',
            'permission_key': 'settings.billing.manage',
            'is_granted': true,
            'is_deleted': false,
          },
          {
            'role': 'receptionist',
            'permission_key': 'settings.billing.manage',
            'is_granted': false,
            'is_deleted': false,
          },
        ],
      };
      final rpcClient = _BillingDeniedRpcClient(tables);
      final c = container(rpcClient: rpcClient);
      addTearDown(c.dispose);

      await c.read(rolePermissionsProvider.future);
      final notifier = c.read(rolePermissionsProvider.notifier);
      notifier.setLocalGrant(role: StaffRole.receptionist, permissionKey: 'settings.billing.manage', isGranted: true);

      final saved = await notifier.saveChanges();
      expect(saved, isFalse);
      expect(rpcClient.lastErrorCode, 'PERMISSION_NOT_DELEGABLE');
    });
  });
}

class _PartialFailureRpcClient extends _RolePermissionsTestClient {
  _PartialFailureRpcClient(super._tables);

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'update_role_permissions') {
      return FakePostgrestRpc({
            'success': false,
            'error_code': 'INVALID_PERMISSION',
            'error_message': 'Permission key is not in the catalog.',
          })
          as PostgrestFilterBuilder<T>;
    }
    return super.rpc<T>(fn, params: params, get: get);
  }
}

class _BillingDeniedRpcClient extends _RolePermissionsTestClient {
  _BillingDeniedRpcClient(super._tables);

  String? lastErrorCode;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'update_role_permission' || fn == 'update_role_permissions') {
      if (params?['p_permission_key'] == 'settings.billing.manage' ||
          _changesIncludeBillingManage(params?['p_changes'])) {
        lastErrorCode = 'PERMISSION_NOT_DELEGABLE';
        return FakePostgrestRpc({
              'success': false,
              'error_code': 'PERMISSION_NOT_DELEGABLE',
              'error_message': 'Billing manage cannot be delegated.',
            })
            as PostgrestFilterBuilder<T>;
      }
    }
    return super.rpc<T>(fn, params: params, get: get);
  }

  bool _changesIncludeBillingManage(Object? changes) {
    if (changes is! List) {
      return false;
    }
    for (final change in changes) {
      if (change is Map && change['permission_key'] == 'settings.billing.manage') {
        return true;
      }
    }
    return false;
  }
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
