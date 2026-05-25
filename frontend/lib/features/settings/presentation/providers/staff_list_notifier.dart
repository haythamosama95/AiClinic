import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/settings_rpc_messages.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

@immutable
class StaffListUiState {
  const StaffListUiState({
    required this.filter,
    required this.staff,
    this.isTogglingActive = false,
    this.togglingStaffId,
    this.actionError,
  });

  final StaffListFilter filter;
  final List<StaffListItem> staff;
  final bool isTogglingActive;
  final String? togglingStaffId;
  final String? actionError;

  StaffListUiState copyWith({
    StaffListFilter? filter,
    List<StaffListItem>? staff,
    bool? isTogglingActive,
    String? togglingStaffId,
    String? actionError,
    bool clearActionError = false,
    bool clearTogglingStaffId = false,
  }) {
    return StaffListUiState(
      filter: filter ?? this.filter,
      staff: staff ?? this.staff,
      isTogglingActive: isTogglingActive ?? this.isTogglingActive,
      togglingStaffId: clearTogglingStaffId ? null : (togglingStaffId ?? this.togglingStaffId),
      actionError: clearActionError ? null : (actionError ?? this.actionError),
    );
  }
}

final staffListProvider = AsyncNotifierProvider<StaffListNotifier, StaffListUiState>(StaffListNotifier.new);

class StaffListNotifier extends AsyncNotifier<StaffListUiState> {
  StaffListFilter _filter = StaffListFilter.active;

  @override
  Future<StaffListUiState> build() async {
    final auth = ref.read(authSessionProvider);
    if (!AuthRouteGuard.canAccessStaffManagement(auth)) {
      return StaffListUiState(filter: _filter, staff: const []);
    }

    final staff = await ref.read(listStaffUseCaseProvider)(filter: _filter);
    return StaffListUiState(filter: _filter, staff: staff);
  }

  Future<void> setFilter(StaffListFilter filter) async {
    _filter = filter;
    state = const AsyncLoading();
    ref.invalidateSelf();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
  }

  void clearActionError() {
    final current = state.value;
    if (current == null || current.actionError == null) {
      return;
    }
    state = AsyncData(current.copyWith(clearActionError: true));
  }

  Future<void> toggleStaffActive(StaffListItem member) async {
    final current = state.value;
    if (current == null) {
      return;
    }

    final targetActive = !member.isActive;
    state = AsyncData(current.copyWith(isTogglingActive: true, togglingStaffId: member.id, clearActionError: true));

    AppLog.info('settings.staff.toggle.start staff_id=${member.id} active=$targetActive');

    try {
      await ref.read(setStaffActiveUseCaseProvider)(staffMemberId: member.id, isActive: targetActive);
      ref.invalidateSelf();
    } on RpcFailure catch (error) {
      AppLog.warning('settings.staff.toggle.rpc_failed code=${error.code}');
      state = AsyncData(
        current.copyWith(isTogglingActive: false, clearTogglingStaffId: true, actionError: staffMessageForRpc(error)),
      );
    } catch (error) {
      AppLog.warning('settings.staff.toggle.failed reason=${error.runtimeType}');
      state = AsyncData(
        current.copyWith(
          isTogglingActive: false,
          clearTogglingStaffId: true,
          actionError: 'Unable to update staff status. Check connectivity and try again.',
        ),
      );
    }
  }
}
