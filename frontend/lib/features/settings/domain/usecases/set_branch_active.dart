import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';

class SetBranchActive {
  const SetBranchActive(this._repository);
  final BranchRepository _repository;

  Future<RpcResult> call({required String branchId, required bool isActive}) {
    return _repository.setBranchActive(
      branchId: branchId,
      isActive: isActive,
    );
  }
}
