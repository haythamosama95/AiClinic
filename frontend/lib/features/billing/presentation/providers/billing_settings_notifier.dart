import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/billing_settings_repository.dart';
import 'package:ai_clinic/features/billing/domain/billing_settings.dart';
import 'package:ai_clinic/features/billing/presentation/billing_rpc_messages.dart';

enum BillingSettingsActionStatus { idle, saving, error, success }

@immutable
class BillingSettingsUiState {
  const BillingSettingsUiState({
    required this.settings,
    this.canEdit = false,
    this.actionStatus = BillingSettingsActionStatus.idle,
    this.errorMessage,
    this.successMessage,
  });

  final BillingSettings settings;
  final bool canEdit;
  final BillingSettingsActionStatus actionStatus;
  final String? errorMessage;
  final String? successMessage;

  bool get isSaving => actionStatus == BillingSettingsActionStatus.saving;

  BillingSettingsUiState copyWith({
    BillingSettings? settings,
    bool? canEdit,
    BillingSettingsActionStatus? actionStatus,
    String? errorMessage,
    String? successMessage,
    bool clearMessages = false,
  }) {
    return BillingSettingsUiState(
      settings: settings ?? this.settings,
      canEdit: canEdit ?? this.canEdit,
      actionStatus: actionStatus ?? this.actionStatus,
      errorMessage: clearMessages ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearMessages ? null : (successMessage ?? this.successMessage),
    );
  }
}

final billingSettingsProvider = AsyncNotifierProvider<BillingSettingsNotifier, BillingSettingsUiState>(
  BillingSettingsNotifier.new,
);

class BillingSettingsNotifier extends AsyncNotifier<BillingSettingsUiState> {
  @override
  Future<BillingSettingsUiState> build() async {
    return _load();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _load());
  }

  Future<bool> updateAllowPartialPayments(bool value) async {
    final permissions = ref.read(permissionServiceProvider);
    if (!permissions.canManageBillingSettings()) {
      _setError('You do not have permission to change billing settings.');
      return false;
    }

    final current = state.value;
    if (current == null) {
      return false;
    }

    state = AsyncData(current.copyWith(actionStatus: BillingSettingsActionStatus.saving, clearMessages: true));

    try {
      await ref.read(billingSettingsRepositoryProvider).update(allowPartialPayments: value);
      final settings = await ref.read(billingSettingsRepositoryProvider).get();
      state = AsyncData(
        current.copyWith(
          settings: settings,
          actionStatus: BillingSettingsActionStatus.success,
          successMessage: 'Billing settings saved.',
        ),
      );
      return true;
    } on RpcFailure catch (error) {
      _setError(billingMessageForRpc(error));
      return false;
    } catch (error) {
      _setError(error.toString());
      return false;
    }
  }

  Future<BillingSettingsUiState> _load() async {
    final permissions = ref.read(permissionServiceProvider);
    final canView = permissions.canViewInvoices() || permissions.canRecordPayment();
    if (!canView) {
      throw StateError('Missing permission to view billing settings.');
    }

    final settings = await ref.read(billingSettingsRepositoryProvider).get();
    return BillingSettingsUiState(settings: settings, canEdit: permissions.canManageBillingSettings());
  }

  void clearMessages() {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(current.copyWith(actionStatus: BillingSettingsActionStatus.idle, clearMessages: true));
  }

  void _setError(String message) {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(current.copyWith(actionStatus: BillingSettingsActionStatus.error, errorMessage: message));
  }
}
