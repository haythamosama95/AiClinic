import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/auth/data/provisioning_repository.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

/// Branches the signed-in staff member may assign when creating accounts.
final staffAssignableBranchesProvider = FutureProvider.autoDispose<List<BranchSummary>>((ref) async {
  final branchIds = ref.watch(authSessionProvider.select((state) => state.context?.branchIds ?? const []));
  if (branchIds.isEmpty) {
    return const [];
  }

  return ref.read(provisioningRepositoryProvider).listBranchesByIds(branchIds);
});
