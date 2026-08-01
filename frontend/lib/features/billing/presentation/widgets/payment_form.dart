import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/providers/billing_settings_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/providers/payment_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/utils/payment_method_l10n.dart';

/// Records a payment against an issued invoice.
class PaymentForm extends ConsumerStatefulWidget {
  const PaymentForm({required this.invoice, required this.onRecorded, super.key});

  final InvoiceDetail invoice;
  final Future<void> Function() onRecorded;

  @override
  ConsumerState<PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends ConsumerState<PaymentForm> {
  final _noteController = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  String? _amount;
  var _submitting = false;

  bool get _amountLocked {
    final settings = ref.watch(billingSettingsProvider).value;
    final isPatientTender = _method != PaymentMethod.insuranceSettlement;
    return settings != null && !settings.allowPartialPayments && isPatientTender;
  }

  String get _resolvedAmount => _amountLocked ? widget.invoice.balance.wireValue : (_amount ?? '');

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    final amount = _resolvedAmount.trim();
    if (amount.isEmpty) {
      appToast(context, const AppToastInput(message: 'Enter a payment amount.', variant: AppToastVariant.danger));
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(paymentNotifierProvider)
          .recordPayment(
            invoiceId: widget.invoice.id,
            method: _method,
            amount: amount,
            note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          );
      if (!mounted) {
        return;
      }
      await widget.onRecorded();
      if (!mounted) {
        return;
      }
      appToast(context, const AppToastInput(message: 'Payment recorded.', variant: AppToastVariant.success));
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      appToast(context, AppToastInput(message: billingMessageForRpc(error), variant: AppToastVariant.danger));
    } catch (_) {
      if (!mounted) {
        return;
      }
      appToast(
        context,
        const AppToastInput(
          message: 'Could not record the payment. Please try again.',
          variant: AppToastVariant.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Balance due', style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)),
            const Spacer(),
            AppMoneyDisplay(
              amount: widget.invoice.balance.asDouble,
              currency: widget.invoice.currency,
              emphasis: true,
              style: AppTypography.h2(
                context,
              ).copyWith(color: colors.textPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppFormField(
                id: 'payment-method',
                label: 'Method',
                child: AppSelect(
                  value: _method.wireValue,
                  disabled: _submitting,
                  options: PaymentMethod.values
                      .map((method) => AppSelectOption(value: method.wireValue, label: method.labelFor(context)))
                      .toList(),
                  onChanged: (value) {
                    final method = PaymentMethod.tryParse(value);
                    if (method != null) {
                      setState(() => _method = method);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: AppFormField(
                id: 'payment-amount',
                label: 'Amount',
                helperText: _amountLocked ? 'Full balance required for this payment method.' : null,
                child: AppMoneyField(
                  key: ValueKey('${_method.name}-${widget.invoice.balance.wireValue}'),
                  currency: widget.invoice.currency,
                  disabled: _submitting || _amountLocked,
                  initialValue: _amountLocked ? widget.invoice.balance.asDouble : null,
                  onChanged: _amountLocked ? null : (value) => _amount = value,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space3),
        AppFormField(
          id: 'payment-note',
          label: 'Note',
          child: AppTextInput(
            controller: _noteController,
            placeholder: 'Optional note for the ledger',
            disabled: _submitting,
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        Align(
          alignment: Alignment.centerRight,
          child: AppButton(
            loading: _submitting,
            onPressed: _submitting ? null : _submit,
            child: const Text('Record payment'),
          ),
        ),
      ],
    );
  }
}
