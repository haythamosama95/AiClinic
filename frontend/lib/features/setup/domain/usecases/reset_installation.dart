import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/repositories/bootstrap_repository.dart';

class ResetInstallation {
  const ResetInstallation(this._repository);
  final BootstrapRepository _repository;

  Future<RpcResult> call() => _repository.resetInstallationForDevelopment();
}
