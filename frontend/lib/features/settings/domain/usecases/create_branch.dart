import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';

class CreateBranch {
  const CreateBranch(this._repository);
  final BranchRepository _repository;

  Future<String> call(CreateBranchInput input) {
    return _repository.createBranch(input);
  }
}
