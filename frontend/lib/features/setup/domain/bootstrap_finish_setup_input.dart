import 'package:ai_clinic/features/setup/domain/bootstrap_branch_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_organization_input.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';

/// Organization, branch, and staff payloads for atomic first-time clinic setup.
class BootstrapFinishSetupInput {
  const BootstrapFinishSetupInput({required this.organization, required this.branch, required this.staffAccounts});

  final BootstrapOrganizationInput organization;
  final BootstrapBranchInput branch;
  final List<CreateStaffAccountInput> staffAccounts;
}
