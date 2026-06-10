import 'package:ai_clinic/features/setup/domain/repositories/provisioning_repository.dart';
import 'package:ai_clinic/features/setup/domain/staff_member_summary.dart';

class ListOrgStaffMembers {
  const ListOrgStaffMembers(this._repository);
  final ProvisioningRepository _repository;

  Future<List<StaffMemberSummary>> call() => _repository.listOrgStaffMembers();
}
