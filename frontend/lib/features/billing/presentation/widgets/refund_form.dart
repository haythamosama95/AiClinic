import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/providers/payment_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/utils/payment_method_l10n.dart';

/// Records a refund against an invoice with collected payments.
class RefundForm extends ConsumerStatefulWidget {
  const RefundForm({
    required this.invoice,
    required this.onRecorded,
    super.key,
  });

  final InvoiceDetail invoice;
  final Future<void> Function() onRecorded;

  @override
  ConsumerState<RefundForm> createState() => _RefundFormState();
}

class _RefundFormState extends ConsumerState<RefundForm> {
  final _noteController = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  String? _amount;
  var _submitting = false;

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    final amount = (_amount ?? '').trim();
    final note = _noteController.text.trim();
    if (amount.isEmpty) {
      appToast(
        context,
        const AppToastInput(
          message: 'Enter a refund amount.',
          variant: AppToastVariant.danger,
        ),
      );
      return;
    }
    if (note.isEmpty) {
      appToast(
        context,
        const AppToastInput(
          message: 'A reason is required for refunds.',
          variant: AppToastVariant.danger,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(paymentNotifierProvider).recordRefund(
            invoiceId: widget.invoice.id,
            method: _method,
            amount: amount,
            note: note,
          );
      if (!mounted) {
        return;
      }
      appToast(
        context,
        const AppToastInput(
          message: 'Refund recorded.',
          variant: AppToastVariant.success,
        ),
      );
      await widget.onRecorded();
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      appToast(
        context,
        AppToastInput(
          message: billingMessageForRpc(error),
          variant: AppToastVariant.danger,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      appToast(
        context,
        const AppToastInput(
          message: 'Could not record the refund. Please try again.',
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
        Text(
          'Record refund',
          style: AppTypography.bodyStrong(
            context,
          ).copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space4),
        AppFormField(
          id: 'refund-method',
          label: 'Method',
          child: AppSelect(
            value: _method.wireValue,
            disabled: _submitting,
            options: PaymentMethod.values
                .map(
                  (method) => AppSelectOption(
                    value: method.wireValue,
                    label: method.labelFor(context),
                  ),
                )
                .toList(),
            onChanged: (value) {
              final method = PaymentMethod.tryParse(value);
              if (method != null) {
                setState(() => _method = method);
              }
            },
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        AppFormField(
          id: 'refund-amount',
          label: 'Amount',
          child: AppMoneyField(
            currency: widget.invoice.currency,
            disabled: _submitting,
            onChanged: (value) => _amount = value,
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        AppFormField(
          id: 'refund-reason',
          label: 'Reason',
          child: AppTextarea(
            controller: _noteController,
            placeholder: 'Why is this amount being refunded?',
            rows: 3,
            disabled: _submitting,
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        Align(
          alignment: Alignment.centerRight,
          child: AppButton(
            loading: _submitting,
            onPressed: _submitting ? null : _submit,
            child: const Text('Record refund'),
          ),
        ),
      ],
    );
  }
}
