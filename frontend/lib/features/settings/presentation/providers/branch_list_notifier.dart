import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/settings_rpc_messages.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

@immutable
class BranchListUiState {
  const BranchListUiState({
    required this.filter,
    required this.branches,
    this.isTogglingActive = false,
    this.togglingBranchId,
    this.actionError,
    this.lastActiveBranchBlockId,
  });

  final BranchListFilter filter;
  final List<BranchListItem> branches;
  final bool isTogglingActive;
  final String? togglingBranchId;
  final String? actionError;
  final String? lastActiveBranchBlockId;

  BranchListUiState copyWith({
    BranchListFilter? filter,
    List<BranchListItem>? branches,
    bool? isTogglingActive,
    String? togglingBranchId,
    String? actionError,
    String? lastActiveBranchBlockId,
    bool clearActionError = false,
    bool clearLastActiveBlock = false,
  }) {
    return BranchListUiState(
      filter: filter ?? this.filter,
      branches: branches ?? this.branches,
      isTogglingActive: isTogglingActive ?? this.isTogglingActive,
      togglingBranchId: togglingBranchId,
      actionError: clearActionError ? null : (actionError ?? this.actionError),
      lastActiveBranchBlockId: clearLastActiveBlock ? null : (lastActiveBranchBlockId ?? this.lastActiveBranchBlockId),
    );
  }
}

final branchListProvider = AsyncNotifierProvider<BranchListNotifier, BranchListUiState>(BranchListNotifier.new);

class BranchListNotifier extends AsyncNotifier<BranchListUiState> {
  BranchListFilter _filter = BranchListFilter.active;

  @override
  Future<BranchListUiState> build() async {
    final auth = ref.read(authSessionProvider);
    if (!AuthRouteGuard.canAccessBranchManagement(auth)) {
      return BranchListUiState(filter: _filter, branches: const []);
    }

    final orgId = auth.context!.organizationId;
    if (orgId == null || orgId.isEmpty) {
      throw StateError('Missing organization id in session');
    }
    final branches = await ref.read(listBranchesUseCaseProvider)(organizationId: orgId, filter: _filter);

    return BranchListUiState(filter: _filter, branches: branches);
  }

  Future<void> setFilter(BranchListFilter filter) async {
    _filter = filter;
    state = const AsyncLoading();
    ref.invalidateSelf();
  }

  /// Fetches the latest branch list from the server (e.g. when opening the list page).
  Future<void> reload() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
  }

  void clearLastActiveBranchBlock() {
    final current = state.value;
    if (current == null || current.lastActiveBranchBlockId == null) {
      return;
    }
    state = AsyncData(current.copyWith(clearLastActiveBlock: true));
  }

  void clearActionError() {
    final current = state.value;
    if (current == null || current.actionError == null) {
      return;
    }
    state = AsyncData(current.copyWith(clearActionError: true));
  }

  /// Returns `true` when deactivation was blocked as the last active branch.
  Future<bool> toggleBranchActive(BranchListItem branch) async {
    final current = state.value;
    if (current == null) {
      return false;
    }

    final targetActive = !branch.isActive;
    state = AsyncData(
      current.copyWith(
        isTogglingActive: true,
        togglingBranchId: branch.id,
        clearActionError: true,
        clearLastActiveBlock: true,
      ),
    );

    AppLog.info('settings.branch.toggle.start branch_id=${branch.id} active=$targetActive');

    try {
      await ref.read(setBranchActiveUseCaseProvider)(branchId: branch.id, isActive: targetActive);
      ref.invalidateSelf();
      return false;
    } on RpcFailure catch (error) {
      AppLog.warning('settings.branch.toggle.rpc_failed code=${error.code}');
      if (error.code == 'LAST_ACTIVE_BRANCH') {
        state = AsyncData(
          current.copyWith(isTogglingActive: false, togglingBranchId: null, lastActiveBranchBlockId: branch.id),
        );
        return true;
      }

      state = AsyncData(
        current.copyWith(isTogglingActive: false, togglingBranchId: null, actionError: branchMessageForRpc(error)),
      );
      return false;
    } catch (error) {
      AppLog.warning('settings.branch.toggle.failed reason=${error.runtimeType}');
      state = AsyncData(
        current.copyWith(
          isTogglingActive: false,
          togglingBranchId: null,
          actionError: 'Unable to update branch status. Check connectivity and try again.',
        ),
      );
      return false;
    }
  }
}
