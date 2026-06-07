import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:ai_clinic/features/shifts/domain/shift_detail.dart';
import 'package:ai_clinic/features/shifts/domain/shift_overlap_conflict.dart';

/// Mutation lifecycle on shift detail (V1-7 US3–US4).
enum ShiftDetailMutationStatus { idle, saving, stale, error }

@immutable
class ShiftDetailState {
  const ShiftDetailState({
    required this.detail,
    this.mutationStatus = ShiftDetailMutationStatus.idle,
    this.mutationError,
    this.overlapConflicts = const [],
    this.pendingAddStaffIds = const {},
  });

  final ShiftDetail detail;
  final ShiftDetailMutationStatus mutationStatus;
  final String? mutationError;
  final List<ShiftOverlapConflict> overlapConflicts;
  final Set<String> pendingAddStaffIds;

  bool get canMutateAssignments => !detail.isReadOnly;

  bool get canEditShift => !detail.isReadOnly;

  bool get isSaving => mutationStatus == ShiftDetailMutationStatus.saving;

  ShiftDetailState copyWith({
    ShiftDetail? detail,
    ShiftDetailMutationStatus? mutationStatus,
    String? mutationError,
    List<ShiftOverlapConflict>? overlapConflicts,
    Set<String>? pendingAddStaffIds,
    bool clearMutationError = false,
    bool clearOverlapConflicts = false,
    bool clearPendingAddStaffIds = false,
  }) {
    return ShiftDetailState(
      detail: detail ?? this.detail,
      mutationStatus: mutationStatus ?? this.mutationStatus,
      mutationError: clearMutationError ? null : (mutationError ?? this.mutationError),
      overlapConflicts: clearOverlapConflicts ? const [] : (overlapConflicts ?? this.overlapConflicts),
      pendingAddStaffIds: clearPendingAddStaffIds ? const {} : (pendingAddStaffIds ?? this.pendingAddStaffIds),
    );
  }
}

final shiftDetailProvider = AsyncNotifierProvider.autoDispose.family<ShiftDetailNotifier, ShiftDetailState, String>(
  ShiftDetailNotifier.new,
);

class ShiftDetailNotifier extends AsyncNotifier<ShiftDetailState> {
  ShiftDetailNotifier(this.shiftId);

  final String shiftId;

  @override
  Future<ShiftDetailState> build() async {
    return ShiftDetailState(detail: await _loadDetail());
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = AsyncData(ShiftDetailState(detail: await _loadDetail()));
  }

  void setPendingAddStaffIds(Set<String> staffIds) {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(pendingAddStaffIds: staffIds, clearMutationError: true, clearOverlapConflicts: true),
    );
  }

  Future<bool> addPendingStaff() async {
    final current = state.value;
    if (current == null || current.pendingAddStaffIds.isEmpty) {
      return false;
    }

    final assignedIds = {for (final assignment in current.detail.assignments) assignment.staffMemberId};
    final toAdd = current.pendingAddStaffIds.difference(assignedIds).toList(growable: false);
    if (toAdd.isEmpty) {
      state = AsyncData(current.copyWith(clearPendingAddStaffIds: true));
      return true;
    }

    return _runMutation(
      mutate: (repo, expectedUpdatedAt) =>
          repo.modifyAssignments(shiftId: current.detail.id, expectedUpdatedAt: expectedUpdatedAt, addStaffIds: toAdd),
      onSuccess: (detail) => current.copyWith(detail: detail, clearPendingAddStaffIds: true),
    );
  }

  Future<bool> removeAssignment({required String staffMemberId}) async {
    final current = state.value;
    if (current == null || staffMemberId.trim().isEmpty) {
      return false;
    }

    return _runMutation(
      mutate: (repo, expectedUpdatedAt) => repo.modifyAssignments(
        shiftId: current.detail.id,
        expectedUpdatedAt: expectedUpdatedAt,
        removeStaffIds: [staffMemberId.trim()],
      ),
      onSuccess: (detail) => current.copyWith(detail: detail),
    );
  }

  Future<bool> updateShift({
    required DateTime shiftDate,
    required String startTime,
    required String endTime,
    String? notes,
  }) async {
    final current = state.value;
    if (current == null) {
      return false;
    }

    return _runMutation(
      mutate: (repo, expectedUpdatedAt) => repo.updateShift(
        shiftId: current.detail.id,
        expectedUpdatedAt: expectedUpdatedAt,
        shiftDate: shiftDate,
        startTime: startTime,
        endTime: endTime,
        notes: notes,
      ),
      onSuccess: (detail) => current.copyWith(detail: detail),
    );
  }

  Future<bool> cancelShift() async {
    final current = state.value;
    if (current == null) {
      return false;
    }

    return _runMutation(
      mutate: (repo, expectedUpdatedAt) =>
          repo.cancelShift(shiftId: current.detail.id, expectedUpdatedAt: expectedUpdatedAt),
      reloadAfterSuccess: false,
      onSuccess: (detail) => current.copyWith(detail: detail),
    );
  }

  Future<bool> _runMutation({
    required Future<void> Function(ShiftRepository repo, DateTime expectedUpdatedAt) mutate,
    required ShiftDetailState Function(ShiftDetail detail) onSuccess,
    bool reloadAfterSuccess = true,
  }) async {
    final current = state.value;
    if (current == null) {
      return false;
    }

    final expectedUpdatedAt = current.detail.updatedAt;
    if (expectedUpdatedAt == null) {
      state = AsyncData(
        current.copyWith(
          mutationStatus: ShiftDetailMutationStatus.error,
          mutationError: 'Shift metadata is missing an updated timestamp. Reload and try again.',
        ),
      );
      return false;
    }

    state = AsyncData(
      current.copyWith(
        mutationStatus: ShiftDetailMutationStatus.saving,
        clearMutationError: true,
        clearOverlapConflicts: true,
      ),
    );

    try {
      final repo = ref.read(shiftRepositoryProvider);
      await mutate(repo, expectedUpdatedAt);
      if (!reloadAfterSuccess) {
        state = AsyncData(onSuccess(current.detail).copyWith(mutationStatus: ShiftDetailMutationStatus.idle));
        return true;
      }

      final detail = await repo.getShiftDetail(shiftId: current.detail.id);
      state = AsyncData(onSuccess(detail).copyWith(mutationStatus: ShiftDetailMutationStatus.idle));
      return true;
    } on RpcFailure catch (error) {
      final currentAfter = state.value ?? current;
      if (error.code == 'stale_shift') {
        state = AsyncData(
          currentAfter.copyWith(mutationStatus: ShiftDetailMutationStatus.stale, mutationError: _messageForRpc(error)),
        );
        return false;
      }

      if (error.code == 'shift_overlap') {
        state = AsyncData(
          currentAfter.copyWith(
            mutationStatus: ShiftDetailMutationStatus.error,
            overlapConflicts: ShiftRepository.parseOverlapConflicts(error.message),
          ),
        );
        return false;
      }

      state = AsyncData(
        currentAfter.copyWith(mutationStatus: ShiftDetailMutationStatus.error, mutationError: _messageForRpc(error)),
      );
      return false;
    } catch (error) {
      final currentAfter = state.value ?? current;
      state = AsyncData(
        currentAfter.copyWith(mutationStatus: ShiftDetailMutationStatus.error, mutationError: error.toString()),
      );
      return false;
    }
  }

  Future<ShiftDetail> _loadDetail() async {
    if (!ref.read(permissionServiceProvider).canViewShifts()) {
      throw RpcFailure(
        const RpcResult(success: false, errorCode: 'permission_denied', errorMessage: 'permission_denied'),
      );
    }

    return ref.read(shiftRepositoryProvider).getShiftDetail(shiftId: shiftId);
  }

  static String _messageForRpc(RpcFailure error) {
    return switch (error.code) {
      'stale_shift' => 'This shift was updated elsewhere. Reload and try again.',
      'staff_not_eligible' => 'A selected staff member is inactive or not assigned to this branch.',
      'staff_already_assigned' => 'That staff member is already assigned to this shift.',
      'shift_cancelled' => 'This shift was cancelled and can no longer be changed.',
      'shift_read_only_past_date' => 'Past shifts are read-only and cannot be edited.',
      'permission_denied' => 'You do not have permission to change this shift.',
      _ => error.message,
    };
  }
}
