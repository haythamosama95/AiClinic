import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_branch_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_dummy_data.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_organization_input.dart';
import 'package:ai_clinic/features/setup/domain/usecases/setup_use_case_providers.dart';

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

enum SetupWizardStep { organization, branch, complete }

@immutable
class SetupOrganizationDraft {
  const SetupOrganizationDraft({required this.name, this.logoUrl, required this.currencyCode, required this.timezone});

  final String name;
  final String? logoUrl;
  final String currencyCode;
  final String timezone;
}

@immutable
class SetupUiState {
  const SetupUiState({
    this.step = SetupWizardStep.organization,
    this.isSubmitting = false,
    this.errorMessage,
    this.organizationDraft,
    this.organizationId,
    this.branchId,
    this.hasShownPasswordWarning = false,
  });

  final SetupWizardStep step;
  final bool isSubmitting;
  final String? errorMessage;
  final SetupOrganizationDraft? organizationDraft;
  final String? organizationId;
  final String? branchId;
  final bool hasShownPasswordWarning;

  SetupUiState copyWith({
    SetupWizardStep? step,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
    SetupOrganizationDraft? organizationDraft,
    bool clearOrganizationDraft = false,
    String? organizationId,
    String? branchId,
    bool? hasShownPasswordWarning,
  }) {
    return SetupUiState(
      step: step ?? this.step,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      organizationDraft: clearOrganizationDraft ? null : (organizationDraft ?? this.organizationDraft),
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
    state = state.copyWith(step: SetupWizardStep.organization, clearError: true, organizationId: null, branchId: null);
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

  /// Persists organization and branch with preset dev values (debug UI only).
  Future<bool> finishSetupWithDummyData() async {
    AppLog.info('setup.dev_dummy_fill.start');
    state = state.copyWith(
      clearError: true,
      organizationDraft: const SetupOrganizationDraft(
        name: BootstrapDummyData.organizationName,
        currencyCode: BootstrapDummyData.currencyCode,
        timezone: BootstrapDummyData.timezone,
      ),
      step: SetupWizardStep.branch,
    );

    return finishSetup(
      branchName: BootstrapDummyData.branchName,
      branchCode: BootstrapDummyData.branchCode,
      address: BootstrapDummyData.branchAddress,
      phone: BootstrapDummyData.branchPhone,
      mapsUrl: BootstrapDummyData.branchMapsUrl,
    );
  }

  /// Persists organization and branch together after both wizard steps are complete.
  Future<bool> finishSetup({
    required String branchName,
    required String branchCode,
    required String address,
    required String phone,
    required String mapsUrl,
  }) async {
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

    state = state.copyWith(isSubmitting: true, clearError: true);
    AppLog.info('setup.finish_setup.start');

    try {
      final organizationId = await ref.read(createOrganizationUseCaseProvider)(
        BootstrapOrganizationInput(
          name: draft.name,
          logoUrl: draft.logoUrl,
          currencyCode: draft.currencyCode,
          timezone: draft.timezone,
        ),
      );
      AppLog.info('setup.finish_setup.organization_created id=$organizationId');

      final branchId = await ref.read(createBootstrapBranchUseCaseProvider)(
        BootstrapBranchInput(
          organizationId: organizationId,
          name: branchName.trim(),
          code: branchCode.trim(),
          address: address.trim(),
          phone: phone.trim(),
          mapsUrl: mapsUrl.trim(),
        ),
      );
      AppLog.info('setup.finish_setup.branch_created id=$branchId');

      await ref.read(authSessionProvider.notifier).refreshSessionContext();

      state = state.copyWith(
        isSubmitting: false,
        organizationId: organizationId,
        branchId: branchId,
        step: SetupWizardStep.complete,
        clearOrganizationDraft: true,
      );
      return true;
    } on RpcFailure catch (error) {
      AppLog.warning('setup.finish_setup.rpc_failed code=${error.code}');
      state = state.copyWith(isSubmitting: false, errorMessage: setupMessageForRpc(error));
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

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
