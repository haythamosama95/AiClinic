import 'package:ai_clinic/features/settings/domain/permission_matrix_row.dart';
import 'package:ai_clinic/features/settings/domain/repositories/role_permissions_repository.dart';

class FetchPermissionMatrix {
  const FetchPermissionMatrix(this._repository);
  final RolePermissionsRepository _repository;

  Future<List<PermissionMatrixRow>> call() => _repository.fetchMatrix();
}
