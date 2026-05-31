import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';

/// Active organization branches for appointment scheduling views.
///
/// Invalidate after branch create/update so working hours stay in sync with settings.
final appointmentActiveBranchesProvider = FutureProvider.autoDispose<List<BranchListItem>>((ref) async {
  final orgId = ref.watch(authSessionProvider.select((state) => state.context?.organizationId));
  if (orgId == null || orgId.trim().isEmpty) {
    return const <BranchListItem>[];
  }

  final branches = await ref.read(listBranchesUseCaseProvider)(organizationId: orgId, filter: BranchListFilter.active);
  return branches..sort((a, b) => a.name.compareTo(b.name));
});

/// Loads the latest working schedule for [branchId] from the server.
Future<BranchWorkingSchedule?> loadBranchWorkingSchedule(WidgetRef ref, {required String branchId}) async {
  ref.invalidate(appointmentActiveBranchesProvider);
  final branches = await ref.read(appointmentActiveBranchesProvider.future);
  final branch = branches.where((item) => item.id == branchId).firstOrNull;
  return branch?.workingSchedule ?? BranchWorkingSchedule.defaultSchedule();
}
