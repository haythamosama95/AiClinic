import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/setup/domain/usecases/setup_use_case_providers.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_result.dart';
import 'package:ai_clinic/features/setup/domain/admin_reset_staff_password_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/setup/domain/staff_password_validation.dart';
import 'package:ai_clinic/features/setup/domain/staff_member_summary.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// User-facing messages for provisioning RPC error codes.
String provisioningMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'ORG_SETUP_INCOMPLETE' => 'Create your clinic organization and first branch before adding staff accounts.',
    'FORBIDDEN' => 'You do not have permission to create staff accounts.',
    'USERNAME_EXISTS' => 'A staff account with this username already exists.',
    'INVALID_BRANCH' => 'One or more selected branches are invalid.',
    'INVALID_INPUT' => failure.message,
    'WEAK_PASSWORD' => failure.message,
    'RPC_NOT_APPLIED' => failure.message,
    _ => 'Unable to create the staff account. Check connectivity and try again.',
  };
}

/// User-facing messages for password-reset RPC error codes.
String passwordResetMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'FORBIDDEN' => 'You do not have permission to reset staff passwords.',
    'STAFF_NOT_FOUND' => 'That staff member was not found. Refresh the list and try again.',
    'CROSS_ORG_DENIED' => 'That staff member is outside your clinic organization.',
    'INVALID_INPUT' => failure.message,
    'WEAK_PASSWORD' => failure.message,
    'RPC_NOT_APPLIED' => failure.message,
    _ => 'Unable to reset the password. Check connectivity and try again.',
  };
}

@immutable
class ProvisioningUiState {
  const ProvisioningUiState({
    this.isSubmitting = false,
    this.errorMessage,
    this.staffAccountsCreatedCount = 0,
    this.lastCreated,
    this.lastPasswordReset,
  });

  final bool isSubmitting;
  final String? errorMessage;
  final int staffAccountsCreatedCount;
  final CreateStaffAccountResult? lastCreated;
  final AdminResetStaffPasswordResult? lastPasswordReset;

  ProvisioningUiState copyWith({
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
    int? staffAccountsCreatedCount,
    CreateStaffAccountResult? lastCreated,
    bool clearLastCreated = false,
    AdminResetStaffPasswordResult? lastPasswordReset,
    bool clearLastPasswordReset = false,
  }) {
    return ProvisioningUiState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      staffAccountsCreatedCount: staffAccountsCreatedCount ?? this.staffAccountsCreatedCount,
      lastCreated: clearLastCreated ? null : (lastCreated ?? this.lastCreated),
      lastPasswordReset: clearLastPasswordReset ? null : (lastPasswordReset ?? this.lastPasswordReset),
    );
  }
}

final provisioningNotifierProvider = NotifierProvider<ProvisioningNotifier, ProvisioningUiState>(
  ProvisioningNotifier.new,
);

class ProvisioningNotifier extends Notifier<ProvisioningUiState> {
  @override
  ProvisioningUiState build() => const ProvisioningUiState();

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(clearError: true);
    }
  }

  void clearLastCreated() {
    final lastCreated = state.lastCreated;
    if (lastCreated != null) {
      lastCreated.clearAssignedPassword();
      state = state.copyWith(clearLastCreated: true);
    }
  }

  void clearLastPasswordReset() {
    final lastPasswordReset = state.lastPasswordReset;
    if (lastPasswordReset != null) {
      lastPasswordReset.clearAssignedPassword();
      state = state.copyWith(clearLastPasswordReset: true);
    }
  }

  /// Validates form fields before invoking the RPC.
  Future<CreateStaffAccountResult?> createStaffAccount({
    required String username,
    required String fullName,
    required StaffRole role,
    required List<String> branchIds,
    required String password,
    String? primaryBranchId,
    String? phone,
  }) async {
    final session = ref.read(authSessionProvider).context;
    if (session == null) {
      state = state.copyWith(errorMessage: 'Sign in again to create staff accounts.');
      return null;
    }

    if (session.setupRequired) {
      state = state.copyWith(errorMessage: 'Finish clinic setup before creating staff accounts.');
      return null;
    }

    final caller = session.staffProfile;
    final trimmedName = fullName.trim();
    final usernameError = validateStaffUsername(username);
    if (usernameError != null) {
      state = state.copyWith(errorMessage: usernameError);
      return null;
    }
    final normalizedUsername = normalizeStaffUsername(username);
    if (trimmedName.isEmpty) {
      state = state.copyWith(errorMessage: 'Enter the staff member full name.');
      return null;
    }
    final passwordError = StaffPasswordValidation.validateInitialPassword(password);
    if (passwordError != null) {
      state = state.copyWith(errorMessage: passwordError);
      return null;
    }
    if (branchIds.isEmpty) {
      state = state.copyWith(errorMessage: 'Select at least one branch assignment.');
      return null;
    }

    final roleError = ProvisioningRules.validateRoleChoice(caller, role);
    if (roleError != null) {
      state = state.copyWith(errorMessage: roleError);
      return null;
    }

    final primary = primaryBranchId ?? branchIds.first;
    if (!branchIds.contains(primary)) {
      state = state.copyWith(errorMessage: 'Primary branch must be one of the selected branches.');
      return null;
    }

    state = state.copyWith(isSubmitting: true, clearError: true, clearLastCreated: true);
    AppLog.info('provisioning.create_staff.start role=${role.wireValue}');

    final trimmedPhone = phone?.trim();
    try {
      final result = await ref.read(createStaffAccountUseCaseProvider)(
        CreateStaffAccountInput(
          username: normalizedUsername,
          password: password,
          fullName: trimmedName,
          role: role,
          branchIds: branchIds,
          primaryBranchId: primary,
          phone: trimmedPhone == null || trimmedPhone.isEmpty ? null : trimmedPhone,
        ),
      );

      state = state.copyWith(
        isSubmitting: false,
        lastCreated: result,
        staffAccountsCreatedCount: state.staffAccountsCreatedCount + 1,
      );
      ref.invalidate(staffResetCandidatesProvider);
      AppLog.info('provisioning.create_staff.ok staff_id=${result.staffMemberId}');
      return result;
    } on RpcFailure catch (error) {
      AppLog.warning('provisioning.create_staff.rpc_failed code=${error.code}');
      state = state.copyWith(isSubmitting: false, errorMessage: provisioningMessageForRpc(error));
      return null;
    } catch (error) {
      AppLog.warning('provisioning.create_staff.failed reason=${error.runtimeType}');
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Unable to create the staff account. Check connectivity and try again.',
      );
      return null;
    }
  }

  /// Validates administrator password reset before invoking the RPC.
  Future<AdminResetStaffPasswordResult?> resetStaffPassword({
    required String staffMemberId,
    required String newPassword,
  }) async {
    final session = ref.read(authSessionProvider).context;
    if (session == null) {
      state = state.copyWith(errorMessage: 'Sign in again to reset staff passwords.');
      return null;
    }

    if (session.setupRequired) {
      state = state.copyWith(errorMessage: 'Finish clinic setup before resetting staff passwords.');
      return null;
    }

    if (!ProvisioningRules.canResetStaffPassword(session.staffProfile)) {
      state = state.copyWith(errorMessage: 'Only clinic administrators can reset staff passwords.');
      return null;
    }

    final trimmedId = staffMemberId.trim();
    final trimmedPassword = newPassword.trim();

    if (trimmedId.isEmpty) {
      state = state.copyWith(errorMessage: 'Select a staff member to reset.');
      return null;
    }
    if (trimmedPassword.isEmpty) {
      state = state.copyWith(errorMessage: 'Enter a new password for the staff member.');
      return null;
    }
    if (trimmedPassword.length < 6) {
      state = state.copyWith(errorMessage: 'Password must be at least 6 characters.');
      return null;
    }

    state = state.copyWith(isSubmitting: true, clearError: true, clearLastPasswordReset: true);
    AppLog.info('provisioning.reset_password.start staff_id=$trimmedId');

    try {
      final result = await ref.read(resetStaffPasswordUseCaseProvider)(
        staffMemberId: trimmedId,
        newPassword: trimmedPassword,
      );

      state = state.copyWith(isSubmitting: false, lastPasswordReset: result);
      AppLog.info('provisioning.reset_password.ok staff_id=${result.staffMemberId}');
      return result;
    } on RpcFailure catch (error) {
      AppLog.warning('provisioning.reset_password.rpc_failed code=${error.code}');
      state = state.copyWith(isSubmitting: false, errorMessage: passwordResetMessageForRpc(error));
      return null;
    } catch (error) {
      AppLog.warning('provisioning.reset_password.failed reason=${error.runtimeType}');
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Unable to reset the password. Check connectivity and try again.',
      );
      return null;
    }
  }
}

/// Staff picker for password reset; auto-disposes when leaving the reset screen.
final staffResetCandidatesProvider = FutureProvider.autoDispose<List<StaffMemberSummary>>((ref) async {
  final session = ref.watch(authSessionProvider).context?.staffProfile;
  if (session == null || !ProvisioningRules.canResetStaffPassword(session)) {
    return const [];
  }

  return ref.read(listOrgStaffMembersUseCaseProvider)();
});
