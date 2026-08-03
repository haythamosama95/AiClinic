import 'package:ai_clinic/features/clinic-management/domain/create_branch_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/branch_repository.dart';

class CreateBranch {
  const CreateBranch(this._repository);
  final BranchRepository _repository;

  Future<String> call(CreateBranchInput input) {
    return _repository.createBranch(input);
  }
}
