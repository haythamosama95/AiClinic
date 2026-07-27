import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_filter.dart';
import 'package:ai_clinic/core/domain/clinic/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/create_branch_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_branch_input.dart';

/// Abstract branch list reads and lifecycle mutations.
abstract class BranchRepository {
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  });
  Future<String> createBranch(CreateBranchInput input);
  Future<String> updateBranch(UpdateBranchInput input);
  Future<RpcResult> setBranchActive({required String branchId, required bool isActive});
  Future<RpcResult> deleteBranch({required String branchId});
}
