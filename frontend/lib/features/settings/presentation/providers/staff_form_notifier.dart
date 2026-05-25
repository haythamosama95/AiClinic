import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/settings/presentation/providers/staff_list_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/settings_rpc_messages.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

@immutable
class StaffFormUiState {
  const StaffFormUiState({
    this.existing,
    this.ownerAlreadyExists = false,
    this.isSaving = false,
    this.permissionDenied = false,
    this.errorMessage,
    this.savedStaffId,
  });

  final StaffMemberDetail? existing;
  final bool ownerAlreadyExists;
  final bool isSaving;
  final bool permissionDenied;
  final String? errorMessage;
  final String? savedStaffId;

  bool get isEditMode => existing != null;

  StaffFormUiState copyWith({
    StaffMemberDetail? existing,
    bool? ownerAlreadyExists,
    bool? isSaving,
    bool? permissionDenied,
    String? errorMessage,
    String? savedStaffId,
    bool clearError = false,
    bool clearSavedStaffId = false,
  }) {
    return StaffFormUiState(
      existing: existing ?? this.existing,
      ownerAlreadyExists: ownerAlreadyExists ?? this.ownerAlreadyExists,
      isSaving: isSaving ?? this.isSaving,
      permissionDenied: permissionDenied ?? this.permissionDenied,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      savedStaffId: clearSavedStaffId ? null : (savedStaffId ?? this.savedStaffId),
    );
  }
}

final staffFormProvider = AsyncNotifierProvider.autoDispose.family<StaffFormNotifier, StaffFormUiState, String?>(
  StaffFormNotifier.new,
);

class StaffFormNotifier extends AsyncNotifier<StaffFormUiState> {
  StaffFormNotifier(this._staffId);

  final String? _staffId;

  @override
  Future<StaffFormUiState> build() async {
    final auth = ref.read(authSessionProvider);
    if (!AuthRouteGuard.canAccessStaffManagement(auth)) {
      return const StaffFormUiState(permissionDenied: true);
    }

    final caller = auth.context!.staffProfile;
    final ownerAlreadyExists =
        await ref.read(organizationHasOwnerUseCaseProvider)() ||
        ProvisioningRules.inferOwnerAlreadyExists(caller);

    final staffId = _staffId;
    if (staffId == null) {
      return StaffFormUiState(ownerAlreadyExists: ownerAlreadyExists);
    }

    final existing = await ref.read(fetchStaffMemberUseCaseProvider)(staffId);
    if (existing == null) {
      return StaffFormUiState(
        ownerAlreadyExists: ownerAlreadyExists,
        errorMessage: 'Staff member $staffId was not found. Return to the staff list and try again.',
      );
    }

    return StaffFormUiState(existing: existing, ownerAlreadyExists: ownerAlreadyExists);
  }

  List<StaffRole> selectableRoles() {
    final auth = ref.read(authSessionProvider).context?.staffProfile;
    if (auth == null) {
      return const [];
    }
    return ProvisioningRules.selectableRoles(auth, ownerAlreadyExists: state.value?.ownerAlreadyExists ?? true);
  }

  String? validateRoleChoice(StaffRole role) {
    final auth = ref.read(authSessionProvider).context?.staffProfile;
    if (auth == null) {
      return 'Sign in again to manage staff.';
    }
    return ProvisioningRules.validateRoleChoice(
      auth,
      role,
      ownerAlreadyExists: state.value?.ownerAlreadyExists ?? true,
    );
  }

  Future<String?> saveEdit({
    required String fullName,
    required StaffRole role,
    required List<String> branchIds,
    String? phone,
    String? primaryBranchId,
  }) async {
    final current = state.value;
    final existing = current?.existing;
    if (current == null || existing == null || current.permissionDenied) {
      return null;
    }

    final roleError = validateRoleChoice(role);
    if (roleError != null) {
      state = AsyncData(current.copyWith(errorMessage: roleError));
      return null;
    }

    final trimmedName = fullName.trim();
    if (trimmedName.isEmpty) {
      state = AsyncData(current.copyWith(errorMessage: 'Full name is required.'));
      return null;
    }
    if (branchIds.isEmpty) {
      state = AsyncData(current.copyWith(errorMessage: 'Select at least one branch assignment.'));
      return null;
    }

    final primary = primaryBranchId ?? branchIds.first;
    if (!branchIds.contains(primary)) {
      state = AsyncData(current.copyWith(errorMessage: 'Primary branch must be one of the selected branches.'));
      return null;
    }

    state = AsyncData(current.copyWith(isSaving: true, clearError: true, clearSavedStaffId: true));
    AppLog.info('settings.staff.save.start staff_id=${existing.id}');

    try {
      final savedId = await ref.read(updateStaffMemberUseCaseProvider)(
        UpdateStaffMemberInput(
          staffMemberId: existing.id,
          fullName: trimmedName,
          role: role,
          branchIds: branchIds,
          phone: phone?.trim(),
          primaryBranchId: primary,
        ),
      );

      state = AsyncData(current.copyWith(isSaving: false, savedStaffId: savedId));
      ref.invalidate(staffListProvider);
      AppLog.info('settings.staff.save.ok staff_id=$savedId');
      return savedId;
    } on RpcFailure catch (error) {
      AppLog.warning('settings.staff.save.rpc_failed code=${error.code}');
      state = AsyncData(current.copyWith(isSaving: false, errorMessage: staffMessageForRpc(error)));
      return null;
    } catch (error) {
      AppLog.warning('settings.staff.save.failed reason=${error.runtimeType}');
      state = AsyncData(
        current.copyWith(
          isSaving: false,
          errorMessage: 'Unable to save staff changes. Check connectivity and try again.',
        ),
      );
      return null;
    }
  }
}
