import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';

/// Loads role permission grants from `roles_permissions` (cached in session context).
class PermissionRepository {
  PermissionRepository(this._client);

  final SupabaseClient _client;

  Future<Set<String>> loadGrantedPermissions(StaffRole role) async {
    final rows = await _client
        .from('roles_permissions')
        .select('permission_key')
        .eq('role', role.wireValue)
        .eq('is_granted', true);

    return parseGrantedPermissionKeys(rows);
  }

  /// Parses PostgREST rows into a deduplicated grant set (testable without network).
  static Set<String> parseGrantedPermissionKeys(List<dynamic> rows) {
    final permissions = <String>{};
    for (final row in rows) {
      if (row is! Map) {
        continue;
      }
      final key = row['permission_key']?.toString().trim();
      if (key != null && key.isNotEmpty) {
        permissions.add(key);
      }
    }
    return permissions;
  }
}

final permissionRepositoryProvider = Provider<PermissionRepository>((ref) {
  return PermissionRepository(ref.watch(supabaseClientProvider));
});
