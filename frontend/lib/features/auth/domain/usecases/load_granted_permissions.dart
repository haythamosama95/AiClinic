import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/repositories/permission_repository.dart';

class LoadGrantedPermissions {
  const LoadGrantedPermissions(this._repository);
  final PermissionRepository _repository;

  Future<Set<String>> call(StaffRole role) {
    return _repository.loadGrantedPermissions(role);
  }
}
