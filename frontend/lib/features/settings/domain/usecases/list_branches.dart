import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';

class ListBranches {
  const ListBranches(this._repository);
  final BranchRepository _repository;

  Future<List<BranchListItem>> call({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) {
    return _repository.listBranches(
      organizationId: organizationId,
      filter: filter,
    );
  }
}
