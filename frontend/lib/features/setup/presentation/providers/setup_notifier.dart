import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_branch_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_finish_setup_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_dummy_data.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_organization_input.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/setup/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/setup/domain/setup_wizard_draft_ids.dart';
import 'package:ai_clinic/features/setup/domain/staff_password_validation.dart';
import 'package:ai_clinic/features/setup/domain/usecases/setup_use_case_providers.dart';
import 'package:ai_clinic/features/setup/presentation/providers/provisioning_notifier.dart';

/// User-facing messages for clinic setup RPC error codes.
String setupMessageForRpc(RpcFailure failure) {
  return switch (failure.code) {
    'ORG_ALREADY_EXISTS' => 'An organization already exists for this installation.',
    'NOT_BOOTSTRAP_ADMIN' => 'Only the bootstrap administrator can perform this clinic setup action.',
    'ORG_NOT_FOUND' => 'The organization could not be found. Restart setup from the beginning.',
    'INVALID_INPUT' => failure.message,
    'RESET_INCOMPLETE' => 'Clinic data could not be cleared. Apply the latest database migrations and try again.',
    'RESET_NOT_APPLIED' => failure.message,
    'RESET_SAFE_DELETE' => failure.message,
    'RESET_DEPENDENCY_BLOCKED' => failure.message,
    _ => 'Unable to save clinic setup. Check connectivity and try again.',
  };
}

enum SetupWizardStep { organization, branch, staff, complete }

@immutable
class SetupOrganizationDraft {
  const SetupOrganizationDraft({required this.name, this.logoUrl, required this.currencyCode, required this.timezone});

  final String name;
  final String? logoUrl;
  final String currencyCode;
  final String timezone;
}

@immutable
class SetupBranchDraft {
  const SetupBranchDraft({
    required this.name,
    required this.code,
    required this.address,
    required this.phone,
    required this.mapsUrl,
  });

  final String name;
  final String code;
  final String address;
  final String phone;
  final String mapsUrl;
}

@immutable
class SetupStaffDraft {
  const SetupStaffDraft({
    required this.username,
    required this.fullName,
    required this.role,
    required this.password,
    required this.branchIds,
    this.primaryBranchId,
  });

  final String username;
  final String fullName;
  final StaffRole role;
  final String password;
  final List<String> branchIds;
  final String? primaryBranchId;
}

@immutable
class SetupUiState {
  const SetupUiState({
    this.step = SetupWizardStep.organization,
    this.isSubmitting = false,
    this.errorMessage,
    this.organizationDraft,
    this.branchDraft,
    this.staffDrafts = const [],
    this.organizationId,
    this.branchId,
    this.hasShownPasswordWarning = false,
  });

  final SetupWizardStep step;
  final bool isSubmitting;
  final String? errorMessage;
  final SetupOrganizationDraft? organizationDraft;
  final SetupBranchDraft? branchDraft;
  final List<SetupStaffDraft> staffDrafts;
  final String? organizationId;
  final String? branchId;
  final bool hasShownPasswordWarning;

  /// Wizard still in progress on `/bootstrap` until Finish submits all setup data.
  bool get isBootstrapWizardInProgress => step != SetupWizardStep.complete;

  SetupUiState copyWith({
    SetupWizardStep? step,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
    SetupOrganizationDraft? organizationDraft,
    bool clearOrganizationDraft = false,
    SetupBranchDraft? branchDraft,
    bool clearBranchDraft = false,
    List<SetupStaffDraft>? staffDrafts,
    bool clearStaffDrafts = false,
    String? organizationId,
    String? branchId,
    bool? hasShownPasswordWarning,
  }) {
    return SetupUiState(
      step: step ?? this.step,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      organizationDraft: clearOrganizationDraft ? null : (organizationDraft ?? this.organizationDraft),
      branchDraft: clearBranchDraft ? null : (branchDraft ?? this.branchDraft),
      staffDrafts: clearStaffDrafts ? const [] : (staffDrafts ?? this.staffDrafts),
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      hasShownPasswordWarning: hasShownPasswordWarning ?? this.hasShownPasswordWarning,
    );
  }
}

final setupNotifierProvider = NotifierProvider<SetupNotifier, SetupUiState>(SetupNotifier.new);

class SetupNotifier extends Notifier<SetupUiState> {
  @override
  SetupUiState build() => const SetupUiState();

  void markPasswordWarningShown() {
    state = state.copyWith(hasShownPasswordWarning: true);
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(clearError: true);
    }
  }

  /// Returns to organization step without touching the database (draft kept in memory).
  void goBackToOrganizationStep() {
    state = state.copyWith(
      step: SetupWizardStep.organization,
      clearError: true,
      organizationId: null,
      branchId: null,
      clearBranchDraft: true,
      clearStaffDrafts: true,
    );
  }

  /// Returns to branch step from staff without touching the database.
  void goBackToBranchStep() {
    if (state.step != SetupWizardStep.staff) {
      return;
    }
    state = state.copyWith(step: SetupWizardStep.branch, clearError: true, clearStaffDrafts: true);
  }

  void markSetupComplete() {
    state = state.copyWith(step: SetupWizardStep.complete, clearError: true);
  }

  void resetWizardState() {
    state = const SetupUiState(hasShownPasswordWarning: true);
  }

  /// Validates organization fields and advances UI only — no RPC until branch step finishes.
  bool continueToBranchStep({
    required String name,
    String? logoUrl,
    required String currencyCode,
    required String timezone,
  }) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      state = state.copyWith(errorMessage: 'Enter your clinic organization name.');
      return false;
    }

    final normalizedCurrency = currencyCode.trim().toUpperCase();
    if (!BootstrapCurrencyOptions.isValid(normalizedCurrency)) {
      state = state.copyWith(errorMessage: 'Select a valid currency code from the list.');
      return false;
    }

    if (!BootstrapTimezoneOptions.isValid(timezone)) {
      state = state.copyWith(errorMessage: 'Select a valid timezone from the list.');
      return false;
    }

    state = state.copyWith(
      clearError: true,
      organizationDraft: SetupOrganizationDraft(
        name: trimmedName,
        logoUrl: _emptyToNull(logoUrl),
        currencyCode: normalizedCurrency,
        timezone: timezone.trim(),
      ),
      step: SetupWizardStep.branch,
      organizationId: null,
      branchId: null,
      clearBranchDraft: true,
      clearStaffDrafts: true,
    );
    return true;
  }

  /// Validates branch fields and advances UI only — no RPC until Finish on the staff step.
  bool continueToStaffStep({
    required String branchName,
    required String branchCode,
    required String address,
    required String phone,
    required String mapsUrl,
  }) {
    final draft = state.organizationDraft;
    if (draft == null) {
      state = state.copyWith(errorMessage: 'Complete organization details first.', step: SetupWizardStep.organization);
      return false;
    }

    if (branchName.trim().isEmpty) {
      state = state.copyWith(errorMessage: 'Enter a name for your first branch.');
      return false;
    }
    if (branchCode.trim().isEmpty) {
      state = state.copyWith(errorMessage: 'Enter a branch code.');
      return false;
    }
    if (address.trim().isEmpty) {
      state = state.copyWith(errorMessage: 'Enter the branch address.');
      return false;
    }
    if (phone.trim().isEmpty) {
      state = state.copyWith(errorMessage: 'Enter a branch phone number.');
      return false;
    }
    if (mapsUrl.trim().isEmpty) {
      state = state.copyWith(errorMessage: 'Enter a maps link for the branch.');
      return false;
    }

    state = state.copyWith(
      clearError: true,
      branchDraft: SetupBranchDraft(
        name: branchName.trim(),
        code: branchCode.trim(),
        address: address.trim(),
        phone: phone.trim(),
        mapsUrl: mapsUrl.trim(),
      ),
      step: SetupWizardStep.staff,
      organizationId: null,
      branchId: null,
      clearStaffDrafts: true,
    );
    return true;
  }

  /// Validates staff fields and stores a draft locally — no RPC until Finish.
  bool addStaffDraft({
    required String username,
    required String fullName,
    required StaffRole role,
    required List<String> branchIds,
    required String password,
    String? primaryBranchId,
  }) {
    final session = ref.read(authSessionProvider).context;
    if (session == null) {
      state = state.copyWith(errorMessage: 'Sign in again to create staff accounts.');
      return false;
    }

    if (state.branchDraft == null) {
      state = state.copyWith(errorMessage: 'Complete branch details first.', step: SetupWizardStep.branch);
      return false;
    }

    final caller = session.staffProfile;
    final trimmedName = fullName.trim();
    final usernameError = validateStaffUsername(username);
    if (usernameError != null) {
      state = state.copyWith(errorMessage: usernameError);
      return false;
    }
    final normalizedUsername = normalizeStaffUsername(username);
    if (trimmedName.isEmpty) {
      state = state.copyWith(errorMessage: 'Enter the staff member full name.');
      return false;
    }
    final passwordError = StaffPasswordValidation.validateInitialPassword(password);
    if (passwordError != null) {
      state = state.copyWith(errorMessage: passwordError);
      return false;
    }
    if (branchIds.isEmpty) {
      state = state.copyWith(errorMessage: 'Select at least one branch assignment.');
      return false;
    }

    final roleError = ProvisioningRules.validateRoleChoice(caller, role);
    if (roleError != null) {
      state = state.copyWith(errorMessage: roleError);
      return false;
    }

    final primary = primaryBranchId ?? branchIds.first;
    if (!branchIds.contains(primary)) {
      state = state.copyWith(errorMessage: 'Primary branch must be one of the selected branches.');
      return false;
    }

    final duplicateUsername = state.staffDrafts.any((draft) => draft.username == normalizedUsername);
    if (duplicateUsername) {
      state = state.copyWith(errorMessage: 'A staff account with this username is already in the setup list.');
      return false;
    }

    state = state.copyWith(
      clearError: true,
      staffDrafts: [
        ...state.staffDrafts,
        SetupStaffDraft(
          username: normalizedUsername,
          fullName: trimmedName,
          role: role,
          password: password,
          branchIds: List<String>.from(branchIds),
          primaryBranchId: primary,
        ),
      ],
    );
    return true;
  }

  /// Wipes org/branch data via dev RPC and reloads session claims for another setup run.
  Future<bool> resetInstallationForDevelopment() async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    AppLog.info('setup.dev_reset.start');

    try {
      final result = await ref.read(resetInstallationUseCaseProvider)();
      AppLog.info(
        'setup.dev_reset.rpc_ok orgs=${result.data?['organizations_deleted']} '
        'branches=${result.data?['branches_deleted']}',
      );

      await ref.read(authSessionProvider.notifier).refreshSessionContext();
      AppLog.info(
        'setup.dev_reset.session_refreshed setup_required=${ref.read(authSessionProvider).context?.setupRequired}',
      );

      resetWizardState();
      state = state.copyWith(isSubmitting: false);
      return true;
    } on RpcFailure catch (error) {
      AppLog.warning('setup.dev_reset.rpc_failed code=${error.code}');
      state = state.copyWith(isSubmitting: false, errorMessage: setupMessageForRpc(error));
      return false;
    } catch (error) {
      AppLog.warning('setup.dev_reset.failed reason=${error.runtimeType} detail=$error');
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Unable to reset clinic data. Check connectivity and try again.',
      );
      return false;
    }
  }

  /// Persists organization, branch, and a dummy administrator with preset dev values (debug UI only).
  Future<bool> finishSetupWithDummyData() async {
    AppLog.info('setup.dev_dummy_fill.start');
    state = state.copyWith(
      clearError: true,
      organizationDraft: const SetupOrganizationDraft(
        name: BootstrapDummyData.organizationName,
        currencyCode: BootstrapDummyData.currencyCode,
        timezone: BootstrapDummyData.timezone,
      ),
      branchDraft: const SetupBranchDraft(
        name: BootstrapDummyData.branchName,
        code: BootstrapDummyData.branchCode,
        address: BootstrapDummyData.branchAddress,
        phone: BootstrapDummyData.branchPhone,
        mapsUrl: BootstrapDummyData.branchMapsUrl,
      ),
      staffDrafts: const [
        SetupStaffDraft(
          username: 'admin',
          fullName: 'Demo Administrator',
          role: StaffRole.administrator,
          password: 'DemoPass1',
          branchIds: [SetupWizardDraftIds.branch],
          primaryBranchId: SetupWizardDraftIds.branch,
        ),
      ],
      step: SetupWizardStep.staff,
    );

    return finishSetup();
  }

  /// Persists organization, branch, and all staff drafts together when Finish is pressed.
  Future<bool> finishSetup() async {
    final orgDraft = state.organizationDraft;
    if (orgDraft == null) {
      state = state.copyWith(errorMessage: 'Complete organization details first.', step: SetupWizardStep.organization);
      return false;
    }

    final branchDraft = state.branchDraft;
    if (branchDraft == null) {
      state = state.copyWith(errorMessage: 'Complete branch details first.', step: SetupWizardStep.branch);
      return false;
    }

    if (state.staffDrafts.isEmpty) {
      state = state.copyWith(errorMessage: 'Create at least one staff account to finish setup.');
      return false;
    }

    state = state.copyWith(isSubmitting: true, clearError: true);
    AppLog.info('setup.finish_setup.start staff_count=${state.staffDrafts.length}');

    try {
      final result = await ref.read(finishBootstrapSetupUseCaseProvider)(
        BootstrapFinishSetupInput(
          organization: BootstrapOrganizationInput(
            name: orgDraft.name,
            logoUrl: orgDraft.logoUrl,
            currencyCode: orgDraft.currencyCode,
            timezone: orgDraft.timezone,
          ),
          branch: BootstrapBranchInput(
            organizationId: '',
            name: branchDraft.name,
            code: branchDraft.code,
            address: branchDraft.address,
            phone: branchDraft.phone,
            mapsUrl: branchDraft.mapsUrl,
          ),
          staffAccounts: [
            for (final staffDraft in state.staffDrafts)
              CreateStaffAccountInput(
                username: staffDraft.username,
                password: staffDraft.password,
                fullName: staffDraft.fullName,
                role: staffDraft.role,
                branchIds: staffDraft.branchIds,
                primaryBranchId: staffDraft.primaryBranchId,
              ),
          ],
        ),
      );
      AppLog.info(
        'setup.finish_setup.completed org=${result.organizationId} '
        'branch=${result.branchId} staff_count=${result.staffMemberIds.length}',
      );

      await ref.read(authSessionProvider.notifier).refreshSessionContext();

      state = state.copyWith(
        isSubmitting: false,
        organizationId: result.organizationId,
        branchId: result.branchId,
        step: SetupWizardStep.complete,
        clearOrganizationDraft: true,
        clearBranchDraft: true,
        clearStaffDrafts: true,
      );
      return true;
    } on RpcFailure catch (error) {
      AppLog.warning('setup.finish_setup.rpc_failed code=${error.code}');
      state = state.copyWith(isSubmitting: false, errorMessage: _finishSetupMessageForRpc(error));
      return false;
    } catch (error) {
      AppLog.warning('setup.finish_setup.failed reason=${error.runtimeType}');
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Unable to save clinic setup. Check connectivity and try again.',
      );
      return false;
    }
  }

  static String _finishSetupMessageForRpc(RpcFailure failure) {
    return switch (failure.code) {
      'ORG_SETUP_INCOMPLETE' ||
      'FORBIDDEN' ||
      'USERNAME_EXISTS' ||
      'INVALID_BRANCH' ||
      'WEAK_PASSWORD' ||
      'RPC_NOT_APPLIED' => provisioningMessageForRpc(failure),
      _ => setupMessageForRpc(failure),
    };
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
