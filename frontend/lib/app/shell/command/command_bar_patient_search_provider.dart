import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_query.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';

/// Async patient matches for the command palette query.
///
/// Uses the existing [searchPatientsUseCaseProvider]; returns an empty list when
/// the query is empty, invalid, or the user cannot access patient search.
final commandBarPatientSearchProvider =
    FutureProvider.family<List<PatientListItem>, String>((ref, query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty || !PatientSearchQuery.canInvokeRpc(trimmed)) {
    return const [];
  }

  final auth = ref.watch(authSessionProvider);
  if (!AuthRouteGuard.canAccessPatientList(auth)) {
    return const [];
  }

  final branchId = auth.context?.activeBranchId;
  if (branchId == null || branchId.isEmpty) {
    return const [];
  }

  final page = await ref.read(searchPatientsUseCaseProvider)(
    query: trimmed,
    scope: PatientListScope.thisBranch,
    branchId: branchId,
    limit: 5,
    offset: 0,
  );
  return page.items;
});
