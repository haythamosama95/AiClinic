import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/repositories/role_permissions_repository.dart';

class UpdateRolePermission {
  const UpdateRolePermission(this._repository);
  final RolePermissionsRepository _repository;

  Future<void> call({
    required StaffRole role,
    required String permissionKey,
    required bool isGranted,
  }) {
    return _repository.updateRolePermission(
      role: role,
      permissionKey: permissionKey,
      isGranted: isGranted,
    );
  }
}
