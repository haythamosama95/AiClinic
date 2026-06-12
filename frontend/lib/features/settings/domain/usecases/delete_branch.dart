import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';

class DeleteBranch {
  const DeleteBranch(this._repository);
  final BranchRepository _repository;

  Future<RpcResult> call({required String branchId}) {
    return _repository.deleteBranch(branchId: branchId);
  }
}
