import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_finish_setup_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_finish_setup_result.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_organization_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_branch_input.dart';

/// Abstract bootstrap operations for first-time clinic setup.
abstract class BootstrapRepository {
  Future<String> createOrganization(BootstrapOrganizationInput input);
  Future<String> createBranch(BootstrapBranchInput input);
  Future<BootstrapFinishSetupResult> finishSetup(BootstrapFinishSetupInput input);
  Future<RpcResult> resetInstallationForDevelopment();
}
