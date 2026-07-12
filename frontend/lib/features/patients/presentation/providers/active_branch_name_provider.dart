import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/clinic_management_use_case_providers.dart';

/// Resolves the display name of the user's active branch for registration copy.
final activeBranchNameProvider = FutureProvider<String>((ref) async {
  final organizationId = ref.watch(authSessionProvider.select((session) => session.context?.organizationId));
  final activeBranchId = ref.watch(authSessionProvider.select((session) => session.context?.activeBranchId));

  if (organizationId == null || organizationId.isEmpty) {
    return 'your active branch';
  }

  final branches = await ref.read(listBranchesUseCaseProvider)(organizationId: organizationId);
  return branches.where((branch) => branch.id == activeBranchId).map((branch) => branch.name).firstOrNull ??
      'your active branch';
});
