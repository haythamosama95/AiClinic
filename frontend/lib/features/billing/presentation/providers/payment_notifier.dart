import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/data/billing_settings_repository.dart';
import 'package:ai_clinic/features/billing/data/payment_repository.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';

enum PaymentActionStatus { idle, saving, error, success }

@immutable
class PaymentPanelState {
  const PaymentPanelState({
    required this.allowPartialPayments,
    this.actionStatus = PaymentActionStatus.idle,
    this.errorMessage,
    this.successMessage,
  });

  final bool allowPartialPayments;
  final PaymentActionStatus actionStatus;
  final String? errorMessage;
  final String? successMessage;

  bool get isSaving => actionStatus == PaymentActionStatus.saving;

  PaymentPanelState copyWith({
    bool? allowPartialPayments,
    PaymentActionStatus? actionStatus,
    String? errorMessage,
    String? successMessage,
    bool clearMessages = false,
  }) {
    return PaymentPanelState(
      allowPartialPayments: allowPartialPayments ?? this.allowPartialPayments,
      actionStatus: actionStatus ?? this.actionStatus,
      errorMessage: clearMessages ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearMessages ? null : (successMessage ?? this.successMessage),
    );
  }
}

final paymentPanelProvider = AsyncNotifierProvider.autoDispose.family<PaymentPanelNotifier, PaymentPanelState, String>(
  PaymentPanelNotifier.new,
);

class PaymentPanelNotifier extends AsyncNotifier<PaymentPanelState> {
  PaymentPanelNotifier(this._invoiceId);

  final String _invoiceId;

  @override
  Future<PaymentPanelState> build() async {
    ref.watch(permissionServiceProvider);
    final settings = await ref.read(billingSettingsRepositoryProvider).get();
    return PaymentPanelState(allowPartialPayments: settings.allowPartialPayments);
  }

  Future<bool> recordPayment({
    required PaymentMethod method,
    required String amount,
    String? reference,
    String? note,
  }) async {
    if (!ref.watch(permissionServiceProvider).canRecordPayment()) {
      _setError('You do not have permission to record payments.');
      return false;
    }

    final current = state.value;
    if (current == null) {
      return false;
    }

    state = AsyncData(current.copyWith(actionStatus: PaymentActionStatus.saving, clearMessages: true));

    try {
      await ref
          .read(paymentRepositoryProvider)
          .recordPayment(invoiceId: _invoiceId, method: method, amount: amount, reference: reference, note: note);
      ref.invalidate(invoiceDetailProvider(_invoiceId));
      state = AsyncData(
        current.copyWith(actionStatus: PaymentActionStatus.success, successMessage: 'Payment recorded successfully.'),
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

  Future<bool> recordRefund({required PaymentMethod method, required String amount, required String note}) async {
    if (!ref.watch(permissionServiceProvider).canRefundPayment()) {
      _setError('You do not have permission to record refunds.');
      return false;
    }

    final current = state.value;
    if (current == null) {
      return false;
    }

    state = AsyncData(current.copyWith(actionStatus: PaymentActionStatus.saving, clearMessages: true));

    try {
      await ref
          .read(paymentRepositoryProvider)
          .recordRefund(invoiceId: _invoiceId, method: method, amount: amount, note: note);
      ref.invalidate(invoiceDetailProvider(_invoiceId));
      state = AsyncData(
        current.copyWith(actionStatus: PaymentActionStatus.success, successMessage: 'Refund recorded successfully.'),
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

  void clearMessages() {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(current.copyWith(actionStatus: PaymentActionStatus.idle, clearMessages: true));
  }

  void _setError(String message) {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(current.copyWith(actionStatus: PaymentActionStatus.error, errorMessage: message));
  }
}
