import 'package:ai_clinic/features/settings/domain/repositories/role_permissions_repository.dart';

class UpdateRolePermissions {
  const UpdateRolePermissions(this._repository);
  final RolePermissionsRepository _repository;

  Future<void> call(Iterable<PermissionMatrixChange> changes) {
    return _repository.updateRolePermissions(changes);
  }
}
