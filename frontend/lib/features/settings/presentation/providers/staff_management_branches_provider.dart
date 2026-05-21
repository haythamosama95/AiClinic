import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

/// Active organization branches available for staff assignment pickers (US3).
final staffManagementBranchesProvider = FutureProvider.autoDispose<List<BranchSummary>>((ref) async {
  final orgId = ref.watch(authSessionProvider.select((s) => s.context?.organizationId));
  if (orgId == null || orgId.isEmpty) {
    return const [];
  }

  final branches = await ref
      .read(branchRepositoryProvider)
      .listBranches(organizationId: orgId, filter: BranchListFilter.active);

  return [
    for (final branch in branches)
      BranchSummary(
        id: branch.id,
        name: branch.name,
        code: branch.code,
        address: branch.address,
        phone: branch.phone,
        mapsUrl: branch.mapsUrl,
      ),
  ];
});
