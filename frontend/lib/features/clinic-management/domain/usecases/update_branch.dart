import 'package:ai_clinic/features/clinic-management/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_branch_input.dart';

class UpdateBranch {
  const UpdateBranch(this._repository);
  final BranchRepository _repository;

  Future<String> call(UpdateBranchInput input) {
    return _repository.updateBranch(input);
  }
}
