import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/data/role_permissions_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/settings_rpc_test_client.dart';
import '../../support/settings_table_test_client.dart';

void main() {
  group('RolePermissionsRepository', () {
    late SettingsRpcTestClient client;
    late RolePermissionsRepository repository;

    setUp(() {
      client = SettingsRpcTestClient();
      repository = RolePermissionsRepository(client);
    });

    test('updateRolePermission sends owner toggle payload', () async {
      await repository.updateRolePermission(
        role: StaffRole.administrator,
        permissionKey: ' settings.manage_branches ',
        isGranted: false,
      );

      expect(client.lastFunction, 'update_role_permission');
      expect(client.lastParams, containsPair('p_role', 'administrator'));
      expect(client.lastParams, containsPair('p_permission_key', 'settings.manage_branches'));
      expect(client.lastParams, containsPair('p_is_granted', false));
    });

    test('fetchMatrix parses permission rows and skips invalid rows', () async {
      final client = SettingsTableTestClient({
        'roles_permissions': [
          {'role': 'owner', 'permission_key': 'settings.manage_staff', 'is_granted': true, 'is_deleted': false},
          {'role': 'doctor', 'permission_key': 'patients.view', 'is_granted': true, 'is_deleted': false},
          {'role': 'doctor', 'permission_key': '', 'is_granted': true, 'is_deleted': false},
        ],
      });
      final matrix = await RolePermissionsRepository(client).fetchMatrix();

      expect(matrix, hasLength(2));
      expect(matrix.map((row) => row.permissionKey), containsAll(['settings.manage_staff', 'patients.view']));
    });

    test('stupid usage: empty permission key throws before RPC', () async {
      expect(
        () => repository.updateRolePermission(role: StaffRole.owner, permissionKey: '   ', isGranted: true),
        throwsA(isA<StateError>()),
      );
    });

    test('advanced: non-privileged role denied matrix write from server', () async {
      client.rpcResults['update_role_permission'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Only owners and administrators may update the permission matrix.',
      };

      expect(
        () => repository.updateRolePermission(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });

    test('corner case: unknown permission key INVALID_PERMISSION', () async {
      client.rpcResults['update_role_permission'] = {
        'success': false,
        'error_code': 'INVALID_PERMISSION',
        'error_message': 'Not in catalog',
      };

      expect(
        () => repository.updateRolePermission(role: StaffRole.owner, permissionKey: 'made.up.key', isGranted: true),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_PERMISSION')),
      );
    });
  });
}
