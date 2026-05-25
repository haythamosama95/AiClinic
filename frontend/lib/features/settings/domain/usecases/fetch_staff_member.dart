import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';

class FetchStaffMember {
  const FetchStaffMember(this._repository);
  final StaffAdminRepository _repository;

  Future<StaffMemberDetail?> call(String staffMemberId) {
    return _repository.fetchStaffMember(staffMemberId);
  }
}
