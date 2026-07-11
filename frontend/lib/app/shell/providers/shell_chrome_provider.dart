import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/branch_selection_notifier.dart';
import 'package:ai_clinic/core/ui/components/app_nav_models.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';

/// Resolved org, branch, and user metadata for [AppSidebar] and [AppTopBar].
class ShellChromeData {
  const ShellChromeData({
    required this.orgName,
    required this.branches,
    required this.currentBranchId,
    required this.currentBranchName,
    required this.user,
  });

  final String orgName;
  final List<AppBranch> branches;
  final String currentBranchId;
  final String currentBranchName;
  final AppUserMenuUser user;
}

final shellChromeProvider = Provider.autoDispose<ShellChromeData>((ref) {
  final auth = ref.watch(authSessionProvider);
  final session = auth.context;

  final orgProfile = ref.watch(clinicSetupOrganizationProvider).asData?.value;
  final orgName = orgProfile?.name ?? session?.organizationId ?? 'Organization';

  final branchesAsync = ref.watch(staffAssignableBranchesProvider);
  final branches = branchesAsync.when(
    data: (summaries) => _branchesForShell(summaries, session, orgName),
    loading: () => _branchesForShell(null, session, orgName),
    error: (_, _) => _branchesForShell(null, session, orgName),
  );

  final currentBranchId =
      ref.watch(branchSelectionProvider) ?? session?.activeBranchId ?? branches.firstOrNull?.id ?? '';
  final currentBranchName =
      branches.where((branch) => branch.id == currentBranchId).map((branch) => branch.name).firstOrNull ??
      (currentBranchId.isNotEmpty ? currentBranchId : 'Branch');

  final user = AppUserMenuUser(
    name: session?.staffProfile.fullName ?? 'Staff',
    role: session?.staffProfile.role.displayLabel ?? 'Staff',
    email: '',
  );

  return ShellChromeData(
    orgName: orgName,
    branches: branches,
    currentBranchId: currentBranchId,
    currentBranchName: currentBranchName,
    user: user,
  );
});

List<AppBranch> _branchesForShell(List<BranchSummary>? summaries, AuthSessionContext? session, String orgName) {
  if (summaries != null && summaries.isNotEmpty) {
    return summaries.map((branch) => AppBranch(id: branch.id, name: branch.name, org: orgName)).toList(growable: false);
  }

  final branchIds = session?.branchIds ?? const <String>[];
  if (branchIds.isEmpty) {
    return const [];
  }

  return branchIds.map((id) => AppBranch(id: id, name: id, org: orgName)).toList(growable: false);
}
