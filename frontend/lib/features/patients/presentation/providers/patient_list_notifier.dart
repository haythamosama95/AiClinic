import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_query.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';

@immutable
class PatientListUiState {
  const PatientListUiState({required this.rows, required this.totalCount, required this.filters, this.searchHint});

  final List<PatientTableRow> rows;
  final int totalCount;
  final PatientListFilters filters;
  final String? searchHint;

  bool get isEmptyResult => rows.isEmpty;

  /// True when the branch has no patients and the user has not searched or filtered.
  bool get isNoPatientsYet => isEmptyResult && totalCount == 0 && searchHint == null && !filters.hasSearchOrFilters;

  /// True when search or filters yield no matching patients.
  bool get isNoMatch => isEmptyResult && !isNoPatientsYet && searchHint == null;
}

/// Loads and paginates patients for the list view.
final patientListProvider = AsyncNotifierProvider<PatientListNotifier, PatientListUiState>(PatientListNotifier.new);

class PatientListNotifier extends AsyncNotifier<PatientListUiState> {
  PatientListFilters _filters = const PatientListFilters();

  PatientListFilters get filters => _filters;

  @override
  Future<PatientListUiState> build() async {
    // Rebuild when the shell active branch changes so this-branch lists stay in sync.
    ref.watch(authSessionProvider.select((state) => state.context?.activeBranchId));
    return _load(_filters);
  }

  Future<void> applyFilters(PatientListFilters filters) async {
    _filters = filters;
    state = await AsyncValue.guard(() => _load(filters));
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() => _load(_filters));
  }

  Future<PatientListUiState> _load(PatientListFilters filters) async {
    final auth = ref.read(authSessionProvider);
    if (!AuthRouteGuard.canAccessPatientList(auth)) {
      return PatientListUiState(rows: const [], totalCount: 0, filters: filters);
    }

    final searchText = filters.searchText.trim();
    final hint = PatientSearchQuery.validationHint(searchText.isEmpty ? null : searchText);
    if (hint != null) {
      return PatientListUiState(rows: const [], totalCount: 0, filters: filters, searchHint: hint);
    }

    final scope = filters.isAllBranchesFilter ? PatientListScope.allBranches : PatientListScope.thisBranch;
    final String? branchId;
    if (scope == PatientListScope.allBranches) {
      branchId = null;
    } else {
      branchId = filters.branchId ?? auth.context?.activeBranchId;
      if (branchId == null || branchId.isEmpty) {
        return PatientListUiState(rows: const [], totalCount: 0, filters: filters);
      }
    }

    final page = await ref.read(searchPatientsUseCaseProvider)(
      query: searchText.isEmpty ? null : searchText,
      scope: scope,
      branchId: branchId,
      limit: filters.pageSize,
      offset: filters.offset,
      lastVisitFilter: filters.lastVisitFilter,
      sortField: filters.sortField,
    );

    return PatientListUiState(
      rows: PatientTableRow.fromItems(page.items),
      totalCount: page.totalCount,
      filters: filters,
    );
  }
}
