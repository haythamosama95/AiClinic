import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';

class DeleteStaffMember {
  const DeleteStaffMember(this._repository);
  final StaffAdminRepository _repository;

  Future<RpcResult> call({required String staffMemberId}) {
    return _repository.deleteStaffMember(staffMemberId: staffMemberId);
  }
}
