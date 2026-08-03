import 'package:ai_clinic/features/clinic-management/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_staff_member_input.dart';

class UpdateStaffMember {
  const UpdateStaffMember(this._repository);
  final StaffAdminRepository _repository;

  Future<String> call(UpdateStaffMemberInput input) {
    return _repository.updateStaffMember(input);
  }
}
