import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_query.dart';
import 'package:ai_clinic/features/patients/presentation/patient_rpc_messages.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_scope_provider.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

/// UI state for [PatientListPage] (US2).
class PatientListUiState {
  const PatientListUiState({
    required this.items,
    required this.totalCount,
    required this.limit,
    required this.offset,
    required this.searchQuery,
    this.validationHint,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  final List<PatientListItem> items;
  final int totalCount;
  final int limit;
  final int offset;
  final String searchQuery;
  final String? validationHint;
  final bool isLoadingMore;
  final String? loadMoreError;

  bool get hasMore => offset + items.length < totalCount;

  PatientListUiState copyWith({
    List<PatientListItem>? items,
    int? totalCount,
    int? limit,
    int? offset,
    String? searchQuery,
    String? validationHint,
    bool clearValidationHint = false,
    bool? isLoadingMore,
    String? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return PatientListUiState(
      items: items ?? this.items,
      totalCount: totalCount ?? this.totalCount,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      searchQuery: searchQuery ?? this.searchQuery,
      validationHint: clearValidationHint ? null : (validationHint ?? this.validationHint),
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError: clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

/// Loads paginated patient list/search for the active scope and branch.
class PatientListNotifier extends AsyncNotifier<PatientListUiState> {
  static const pageSize = 25;

  String _searchQuery = '';

  @override
  Future<PatientListUiState> build() async {
    ref.listen<PatientListScope>(patientListScopeProvider, (previous, next) {
      if (previous != next) {
        reload();
      }
    });

    ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
      final prevBranch = previous?.context?.activeBranchId;
      final nextBranch = next.context?.activeBranchId;
      if (prevBranch != nextBranch) {
        reload();
      }
    });

    return _fetchPage(offset: 0);
  }

  Future<void> reload({String? searchQuery}) async {
    if (searchQuery != null) {
      _searchQuery = searchQuery.trim();
    }

    final hint = PatientSearchQuery.validationHint(_searchQuery);
    if (hint != null) {
      state = AsyncData(
        PatientListUiState(
          items: const [],
          totalCount: 0,
          limit: pageSize,
          offset: 0,
          searchQuery: _searchQuery,
          validationHint: hint,
        ),
      );
      return;
    }

    if (!state.hasValue) {
      state = const AsyncLoading();
    }
    state = await AsyncValue.guard(() => _fetchPage(offset: 0));
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.isLoadingMore || current.validationHint != null) {
      return;
    }

    state = AsyncData(current.copyWith(isLoadingMore: true, clearLoadMoreError: true));

    try {
      final page = await _fetchRpc(offset: current.offset + current.limit);
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...page.items],
          totalCount: page.totalCount,
          limit: page.limit,
          offset: page.offset,
          isLoadingMore: false,
          clearValidationHint: true,
          clearLoadMoreError: true,
        ),
      );
    } catch (error, _) {
      state = AsyncData(
        current.copyWith(
          isLoadingMore: false,
          loadMoreError: error.toString(),
        ),
      );
    }
  }

  Future<PatientListUiState> _fetchPage({required int offset}) async {
    final hint = PatientSearchQuery.validationHint(_searchQuery);
    if (hint != null) {
      return PatientListUiState(
        items: const [],
        totalCount: 0,
        limit: pageSize,
        offset: 0,
        searchQuery: _searchQuery,
        validationHint: hint,
      );
    }

    final page = await _fetchRpc(offset: offset);
    return PatientListUiState(
      items: page.items,
      totalCount: page.totalCount,
      limit: page.limit,
      offset: page.offset,
      searchQuery: _searchQuery,
    );
  }

  Future<PatientSearchPage> _fetchRpc({required int offset}) async {
    final auth = ref.read(authSessionProvider);
    final scope = ref.read(patientListScopeProvider);
    final activeBranchId = auth.context?.activeBranchId;

    if (scope == PatientListScope.thisBranch && (activeBranchId == null || activeBranchId.isEmpty)) {
      throw StateError('Select an active branch before loading patients.');
    }

    try {
      return await ref.read(searchPatientsUseCaseProvider)(
        query: _searchQuery.isEmpty ? null : _searchQuery,
        scope: scope,
        branchId: scope == PatientListScope.thisBranch ? activeBranchId : null,
        limit: pageSize,
        offset: offset,
      );
    } on RpcFailure catch (failure) {
      throw StateError(patientMessageForRpc(failure));
    }
  }
}

final patientListProvider = AsyncNotifierProvider<PatientListNotifier, PatientListUiState>(PatientListNotifier.new);
