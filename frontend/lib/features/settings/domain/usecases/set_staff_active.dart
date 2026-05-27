import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';

class SetStaffActive {
  const SetStaffActive(this._repository);
  final StaffAdminRepository _repository;

  Future<RpcResult> call({required String staffMemberId, required bool isActive}) {
    return _repository.setStaffActive(
      staffMemberId: staffMemberId,
      isActive: isActive,
    );
  }
}
