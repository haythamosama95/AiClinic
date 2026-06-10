import 'package:ai_clinic/features/setup/domain/bootstrap_finish_setup_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_finish_setup_result.dart';
import 'package:ai_clinic/features/setup/domain/repositories/bootstrap_repository.dart';

class FinishBootstrapSetup {
  const FinishBootstrapSetup(this._repository);

  final BootstrapRepository _repository;

  Future<BootstrapFinishSetupResult> call(BootstrapFinishSetupInput input) {
    return _repository.finishSetup(input);
  }
}
