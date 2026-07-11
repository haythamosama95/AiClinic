import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';

final clinicSetupOrganizationProvider = FutureProvider.autoDispose<OrganizationProfile?>((ref) async {
  final organizationId = ref.watch(authSessionProvider.select((session) => session.context?.organizationId));
  if (organizationId == null || organizationId.isEmpty) {
    return null;
  }

  return ref.read(fetchOrganizationProfileUseCaseProvider)(organizationId: organizationId);
});

final clinicSetupBranchesProvider = FutureProvider.autoDispose<List<BranchListItem>>((ref) async {
  final organizationId = ref.watch(authSessionProvider.select((session) => session.context?.organizationId));
  if (organizationId == null || organizationId.isEmpty) {
    return const [];
  }

  return ref.read(listBranchesUseCaseProvider)(organizationId: organizationId);
});
