import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/payment_notifier.dart';

/// Presents refund recording against a paid or partially paid invoice.
Future<bool> showRefundRecordDialog({
  required BuildContext context,
  required WidgetRef ref,
  required InvoiceDetail invoice,
}) {
  return showAppDialog<bool>(
    context,
    size: AppDialogSize.md,
    barrierDismissible: false,
    semanticLabel: 'Record refund',
    builder: (dialogContext, close) {
      return _RefundRecordDialogContent(
        invoice: invoice,
        onClose: () => close(false),
        onRecorded: () => close(true),
      );
    },
  ).then((value) => value ?? false);
}

class _RefundRecordDialogContent extends ConsumerStatefulWidget {
  const _RefundRecordDialogContent({
    required this.invoice,
    required this.onClose,
    required this.onRecorded,
  });

  final InvoiceDetail invoice;
  final VoidCallback onClose;
  final VoidCallback onRecorded;

  @override
  ConsumerState<_RefundRecordDialogContent> createState() => _RefundRecordDialogContentState();
}

class _RefundRecordDialogContentState extends ConsumerState<_RefundRecordDialogContent> {
  PaymentMethod _method = PaymentMethod.cash;
  Decimal? _amount;
  final _noteController = TextEditingController();
  var _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = _amount;
    final note = _noteController.text.trim();
    if (amount == null || amount <= Decimal.zero) {
      setState(() => _errorMessage = 'Enter a valid refund amount greater than zero.');
      return;
    }
    if (note.isEmpty) {
      setState(() => _errorMessage = 'A reason is required for refunds.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(paymentNotifierProvider).recordRefund(
        invoiceId: widget.invoice.id,
        method: _method,
        amount: amount.toStringAsFixed(2),
        note: note,
      );
      ref.invalidate(invoiceDetailViewProvider(widget.invoice.id));
      if (!mounted) {
        return;
      }
      widget.onRecorded();
    } on RpcFailure catch (failure) {
      setState(() {
        _isSaving = false;
        _errorMessage = billingMessageForRpc(failure);
      });
    } catch (error) {
      setState(() {
        _isSaving = false;
        _errorMessage = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final methodOptions = PaymentMethod.values
        .map((method) => AppSelectOption(value: method, label: method.label))
        .toList(growable: false);

    return AppDialog(
      key: const Key('refund_record_dialog'),
      title: 'Record refund',
      description: 'Refunds are stored as negative payments and cannot be edited later.',
      onClose: _isSaving ? null : widget.onClose,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFormField(
            label: 'Method',
            child: AppSelect<PaymentMethod>(
              value: _method,
              options: methodOptions,
              disabled: _isSaving,
              onChanged: (value) => setState(() => _method = value),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          AppFormField(
            label: 'Refund amount',
            child: AppMoneyField(
              currency: widget.invoice.currency,
              value: _amount,
              disabled: _isSaving,
              onValueChange: (value) => setState(() => _amount = value),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          AppFormField(
            label: 'Reason',
            child: AppTextField(
              controller: _noteController,
              hintText: 'Why is this refund being issued?',
              maxLines: 3,
              disabled: _isSaving,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.s3),
            AppAlert(variant: AppAlertVariant.danger, title: _errorMessage!),
          ],
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            disabled: _isSaving,
            onPressed: widget.onClose,
          ),
          const SizedBox(width: AppSpacing.s2),
          AppButton(
            label: 'Record refund',
            variant: AppButtonVariant.danger,
            loading: _isSaving,
            onPressed: _isSaving ? null : _submit,
          ),
        ],
      ),
    );
  }
}
