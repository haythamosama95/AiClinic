import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/update_branch_input.dart';

/// Abstract branch list reads and lifecycle mutations.
abstract class BranchRepository {
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  });
  Future<String> createBranch(CreateBranchInput input);
  Future<String> updateBranch(UpdateBranchInput input);
  Future<RpcResult> setBranchActive({required String branchId, required bool isActive});
}
