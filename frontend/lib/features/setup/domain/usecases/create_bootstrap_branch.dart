import 'package:ai_clinic/features/auth/domain/bootstrap_branch_input.dart';
import 'package:ai_clinic/features/auth/domain/repositories/bootstrap_repository.dart';

class CreateBootstrapBranch {
  const CreateBootstrapBranch(this._repository);
  final BootstrapRepository _repository;

  Future<String> call(BootstrapBranchInput input) {
    return _repository.createBranch(input);
  }
}
