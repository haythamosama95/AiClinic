import 'package:ai_clinic/features/auth/domain/auth_session.dart';

/// Abstract permission grant loading.
abstract class PermissionRepository {
  Future<Set<String>> loadGrantedPermissions(StaffRole role);
}
