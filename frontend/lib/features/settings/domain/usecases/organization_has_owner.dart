import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';

class OrganizationHasOwner {
  const OrganizationHasOwner(this._repository);
  final StaffAdminRepository _repository;

  Future<bool> call() => _repository.organizationHasOwner();
}
