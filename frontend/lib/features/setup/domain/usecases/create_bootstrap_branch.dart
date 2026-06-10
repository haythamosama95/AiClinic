import 'package:ai_clinic/features/setup/domain/bootstrap_branch_input.dart';
import 'package:ai_clinic/features/setup/domain/repositories/bootstrap_repository.dart';

class CreateBootstrapBranch {
  const CreateBootstrapBranch(this._repository);
  final BootstrapRepository _repository;

  Future<String> call(BootstrapBranchInput input) {
    return _repository.createBranch(input);
  }
}
