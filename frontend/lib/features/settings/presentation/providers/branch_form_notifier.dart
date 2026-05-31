import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/update_branch_input.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_branch_providers.dart';
import 'package:ai_clinic/features/settings/presentation/providers/branch_list_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/settings_rpc_messages.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

@immutable
class BranchFormUiState {
  const BranchFormUiState({
    this.existing,
    this.isSaving = false,
    this.permissionDenied = false,
    this.errorMessage,
    this.fieldErrors = const {},
    this.savedBranchId,
  });

  final BranchListItem? existing;
  final bool isSaving;
  final bool permissionDenied;
  final String? errorMessage;
  final Map<String, String> fieldErrors;
  final String? savedBranchId;

  bool get isEditMode => existing != null;

  BranchFormUiState copyWith({
    BranchListItem? existing,
    bool? isSaving,
    bool? permissionDenied,
    String? errorMessage,
    Map<String, String>? fieldErrors,
    String? savedBranchId,
    bool clearError = false,
    bool clearFieldErrors = false,
    bool clearSavedBranchId = false,
  }) {
    return BranchFormUiState(
      existing: existing ?? this.existing,
      isSaving: isSaving ?? this.isSaving,
      permissionDenied: permissionDenied ?? this.permissionDenied,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      fieldErrors: clearFieldErrors ? const {} : (fieldErrors ?? this.fieldErrors),
      savedBranchId: clearSavedBranchId ? null : (savedBranchId ?? this.savedBranchId),
    );
  }
}

/// [branchId] is `null` for create; otherwise loads that branch for edit.
final branchFormProvider = AsyncNotifierProvider.autoDispose.family<BranchFormNotifier, BranchFormUiState, String?>(
  BranchFormNotifier.new,
);

class BranchFormNotifier extends AsyncNotifier<BranchFormUiState> {
  BranchFormNotifier(this._branchId);

  final String? _branchId;

  @override
  Future<BranchFormUiState> build() async {
    final branchId = _branchId;
    final auth = ref.read(authSessionProvider);
    if (!AuthRouteGuard.canAccessBranchManagement(auth)) {
      return const BranchFormUiState(permissionDenied: true);
    }

    if (branchId == null) {
      return const BranchFormUiState();
    }

    final orgId = auth.context!.organizationId;
    if (orgId == null || orgId.isEmpty) {
      throw StateError('Missing organization id in session');
    }

    final branches = await ref.read(listBranchesUseCaseProvider)(organizationId: orgId);
    BranchListItem? existing;
    for (final branch in branches) {
      if (branch.id == branchId) {
        existing = branch;
        break;
      }
    }

    if (existing == null) {
      return BranchFormUiState(
        errorMessage: 'Branch $branchId was not found. Return to the branch list and try again.',
      );
    }

    return BranchFormUiState(existing: existing);
  }

  Future<String?> save({
    required String name,
    required BranchWorkingSchedule workingSchedule,
    String? code,
    String? address,
    String? phone,
    String? mapsUrl,
  }) async {
    final current = state.value;
    if (current == null || current.permissionDenied) {
      return null;
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      state = AsyncData(current.copyWith(fieldErrors: {'name': 'Branch name is required.'}, clearError: true));
      return null;
    }
    final hasWorkingDay = workingSchedule.days.any((day) => day.isWorkingDay);
    if (!hasWorkingDay) {
      state = AsyncData(
        current.copyWith(
          errorMessage: 'Select at least one working day and provide its working hours.',
          clearFieldErrors: true,
          clearSavedBranchId: true,
        ),
      );
      return null;
    }

    state = AsyncData(
      current.copyWith(isSaving: true, clearError: true, clearFieldErrors: true, clearSavedBranchId: true),
    );

    final branchId = _branchId;
    AppLog.info('settings.branch.save.start edit=${branchId != null}');

    try {
      final String savedId;
      if (branchId == null) {
        savedId = await ref.read(createBranchUseCaseProvider)(
          CreateBranchInput(
            name: trimmedName,
            workingSchedule: workingSchedule,
            code: _optionalTrim(code),
            address: _optionalTrim(address),
            phone: _optionalTrim(phone),
            mapsUrl: _optionalTrim(mapsUrl),
          ),
        );
      } else {
        savedId = await ref.read(updateBranchUseCaseProvider)(
          UpdateBranchInput(
            branchId: branchId,
            name: trimmedName,
            workingSchedule: workingSchedule,
            code: _optionalTrim(code),
            address: _optionalTrim(address),
            phone: _optionalTrim(phone),
            mapsUrl: _optionalTrim(mapsUrl),
          ),
        );
      }

      state = AsyncData(current.copyWith(isSaving: false, savedBranchId: savedId));
      ref.invalidate(branchListProvider);
      ref.invalidate(appointmentActiveBranchesProvider);
      AppLog.info('settings.branch.save.ok branch_id=$savedId');
      return savedId;
    } on RpcFailure catch (error) {
      AppLog.warning('settings.branch.save.rpc_failed code=${error.code}');
      final fieldErrors = switch (error.code) {
        'DUPLICATE_CODE' => {'code': branchMessageForRpc(error)},
        'INVALID_INPUT' when error.message.toLowerCase().contains('name') => {'name': error.message},
        'INVALID_INPUT' when error.message.toLowerCase().contains('code') => {'code': error.message},
        _ => <String, String>{},
      };

      state = AsyncData(
        current.copyWith(isSaving: false, errorMessage: branchMessageForRpc(error), fieldErrors: fieldErrors),
      );
      return null;
    } catch (error) {
      AppLog.warning('settings.branch.save.failed reason=${error.runtimeType}');
      state = AsyncData(
        current.copyWith(isSaving: false, errorMessage: 'Unable to save the branch. Check connectivity and try again.'),
      );
      return null;
    }
  }

  static String? _optionalTrim(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
