import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_row.dart';

/// Abstract role permission matrix reads and updates.
abstract class RolePermissionsRepository {
  Future<List<PermissionMatrixRow>> fetchMatrix();
  Future<void> updateRolePermission({
    required StaffRole role,
    required String permissionKey,
    required bool isGranted,
  });
}
