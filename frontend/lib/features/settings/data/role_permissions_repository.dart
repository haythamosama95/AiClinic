import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/data/settings_rpc_repository.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_row.dart';
import 'package:ai_clinic/features/settings/domain/repositories/role_permissions_repository.dart';

/// Steady-state role permission matrix reads and owner/administrator updates.
class RolePermissionsRepositoryImpl with AppRpcInvoker, SettingsRpcInvoker implements RolePermissionsRepository {
  RolePermissionsRepositoryImpl(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get settingsRpcClient => _client;

  @override
  Future<List<PermissionMatrixRow>> fetchMatrix() async {
    final rows = await _client
        .from('roles_permissions')
        .select('role, permission_key, is_granted')
        .eq('is_deleted', false)
        .order('permission_key')
        .order('role');

    final matrix = <PermissionMatrixRow>[];
    for (final row in rows) {
      final parsed = PermissionMatrixRow.fromRow(Map<String, dynamic>.from(row));
      if (parsed != null) {
        matrix.add(parsed);
      }
    }
    return matrix;
  }

  @override
  Future<void> updateRolePermission({
    required StaffRole role,
    required String permissionKey,
    required bool isGranted,
  }) async {
    final key = permissionKey.trim();
    if (key.isEmpty) {
      throw StateError('Permission key is required.');
    }

    await invokeSettingsRpc('update_role_permission', {
      'p_role': role.wireValue,
      'p_permission_key': key,
      'p_is_granted': isGranted,
    });
  }
}

final rolePermissionsRepositoryProvider = Provider<RolePermissionsRepository>((ref) {
  return RolePermissionsRepositoryImpl(ref.watch(supabaseClientProvider));
});
