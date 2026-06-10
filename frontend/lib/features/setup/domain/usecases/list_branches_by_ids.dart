import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/domain/repositories/provisioning_repository.dart';

class ListBranchesByIds {
  const ListBranchesByIds(this._repository);
  final ProvisioningRepository _repository;

  Future<List<BranchSummary>> call(List<String> branchIds) {
    return _repository.listBranchesByIds(branchIds);
  }
}
