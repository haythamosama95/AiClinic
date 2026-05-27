import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/auth/domain/usecases/auth_use_case_providers.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Active assigned branches for the signed-in staff (shell switcher, staff forms).
///
/// [ProvisioningRepository.listBranchesByIds] filters `is_active` and `is_deleted`,
/// matching JWT `branch_ids` from `build_staff_claims`.
final staffAssignableBranchesProvider = FutureProvider.autoDispose<List<BranchSummary>>((ref) async {
  final branchIds = ref.watch(authSessionProvider.select((state) => state.context?.branchIds ?? const []));
  if (branchIds.isEmpty) {
    return const [];
  }

  return ref.read(listBranchesByIdsUseCaseProvider)(branchIds);
});
