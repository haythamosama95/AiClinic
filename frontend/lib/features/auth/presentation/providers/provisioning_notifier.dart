import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/data/provisioning_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/provisioning_rules.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

/// User-facing messages for provisioning RPC error codes.
String provisioningMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'ORG_SETUP_INCOMPLETE' => 'Create your clinic organization and first branch before adding staff accounts.',
    'FORBIDDEN_OWNER_CREATE' => failure.message,
    'FORBIDDEN' => 'You do not have permission to create staff accounts.',
    'EMAIL_EXISTS' => 'A staff account with this email already exists.',
    'INVALID_BRANCH' => 'One or more selected branches are invalid.',
    'INVALID_INPUT' => failure.message,
    'RPC_NOT_APPLIED' => failure.message,
    _ => 'Unable to create the staff account. Check connectivity and try again.',
  };
}

@immutable
class ProvisioningUiState {
  const ProvisioningUiState({
    this.isSubmitting = false,
    this.errorMessage,
    this.ownerAlreadyExists = false,
    this.lastCreated,
  });

  final bool isSubmitting;
  final String? errorMessage;
  final bool ownerAlreadyExists;
  final CreateStaffAccountResult? lastCreated;

  ProvisioningUiState copyWith({
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
    bool? ownerAlreadyExists,
    CreateStaffAccountResult? lastCreated,
    bool clearLastCreated = false,
  }) {
    return ProvisioningUiState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      ownerAlreadyExists: ownerAlreadyExists ?? this.ownerAlreadyExists,
      lastCreated: clearLastCreated ? null : (lastCreated ?? this.lastCreated),
    );
  }
}

final provisioningNotifierProvider = NotifierProvider<ProvisioningNotifier, ProvisioningUiState>(
  ProvisioningNotifier.new,
);

class ProvisioningNotifier extends Notifier<ProvisioningUiState> {
  @override
  ProvisioningUiState build() {
    final caller = ref.read(authSessionProvider).context?.staffProfile;
    final ownerAlreadyExists = caller == null ? false : ProvisioningRules.inferOwnerAlreadyExists(caller);
    return ProvisioningUiState(ownerAlreadyExists: ownerAlreadyExists);
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(clearError: true);
    }
  }

  void clearLastCreated() {
    if (state.lastCreated != null) {
      state = state.copyWith(clearLastCreated: true);
    }
  }

  void markOwnerExists() {
    if (!state.ownerAlreadyExists) {
      state = state.copyWith(ownerAlreadyExists: true);
    }
  }

  /// Validates form fields and FR-022c before invoking the RPC.
  Future<CreateStaffAccountResult?> createStaffAccount({
    required String email,
    required String fullName,
    required StaffRole role,
    required List<String> branchIds,
    required String password,
    String? primaryBranchId,
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
    final trimmedEmail = email.trim();
    final trimmedName = fullName.trim();

    if (trimmedEmail.isEmpty) {
      state = state.copyWith(errorMessage: 'Enter the staff member email address.');
      return null;
    }
    if (!trimmedEmail.contains('@') || trimmedEmail.startsWith('@') || !trimmedEmail.contains('.')) {
      state = state.copyWith(errorMessage: 'Enter a valid email address.');
      return null;
    }
    if (trimmedName.isEmpty) {
      state = state.copyWith(errorMessage: 'Enter the staff member full name.');
      return null;
    }
    if (password.trim().isEmpty) {
      state = state.copyWith(errorMessage: 'Enter an initial password for the new account.');
      return null;
    }
    if (password.length < 6) {
      state = state.copyWith(errorMessage: 'Password must be at least 6 characters.');
      return null;
    }
    if (branchIds.isEmpty) {
      state = state.copyWith(errorMessage: 'Select at least one branch assignment.');
      return null;
    }

    final roleError = ProvisioningRules.validateRoleChoice(caller, role, ownerAlreadyExists: state.ownerAlreadyExists);
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

    try {
      final result = await ref
          .read(provisioningRepositoryProvider)
          .createStaffAccount(
            CreateStaffAccountInput(
              email: trimmedEmail,
              password: password,
              fullName: trimmedName,
              role: role,
              branchIds: branchIds,
              primaryBranchId: primary,
            ),
          );

      if (role == StaffRole.owner) {
        markOwnerExists();
      }

      state = state.copyWith(isSubmitting: false, lastCreated: result);
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
}
