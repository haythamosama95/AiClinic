import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/providers/billing_settings_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/presentation/providers/payment_notifier.dart';

/// Presents payment recording for an issued or partially paid invoice.
Future<bool> showPaymentRecordDialog({
  required BuildContext context,
  required WidgetRef ref,
  required InvoiceDetail invoice,
}) {
  return showAppDialog<bool>(
    context,
    size: AppDialogSize.md,
    barrierDismissible: false,
    semanticLabel: 'Record payment',
    builder: (dialogContext, close) {
      return _PaymentRecordDialogContent(
        invoice: invoice,
        onClose: () => close(false),
        onRecorded: () => close(true),
      );
    },
  ).then((value) => value ?? false);
}

class _PaymentRecordDialogContent extends ConsumerStatefulWidget {
  const _PaymentRecordDialogContent({
    required this.invoice,
    required this.onClose,
    required this.onRecorded,
  });

  final InvoiceDetail invoice;
  final VoidCallback onClose;
  final VoidCallback onRecorded;

  @override
  ConsumerState<_PaymentRecordDialogContent> createState() => _PaymentRecordDialogContentState();
}

class _PaymentRecordDialogContentState extends ConsumerState<_PaymentRecordDialogContent> {
  PaymentMethod _method = PaymentMethod.cash;
  Decimal? _amount;
  final _referenceController = TextEditingController();
  final _noteController = TextEditingController();
  var _isSaving = false;
  String? _errorMessage;

  bool get _lockAmount {
    final settings = ref.read(billingSettingsProvider).value;
    final allowPartial = settings?.allowPartialPayments ?? false;
    return !allowPartial && _method.isPatientTender;
  }

  @override
  void initState() {
    super.initState();
    _amount = Decimal.parse(widget.invoice.balance.wireValue);
  }

  @override
  void dispose() {
    _referenceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool _canAcceptPayment(InvoiceStatus status) {
    return status == InvoiceStatus.issued || status == InvoiceStatus.partiallyPaid;
  }

  Future<void> _submit() async {
    if (!_canAcceptPayment(widget.invoice.status)) {
      setState(() => _errorMessage = 'Payments cannot be recorded on this invoice in its current state.');
      return;
    }

    final amount = _lockAmount
        ? Decimal.parse(widget.invoice.balance.wireValue)
        : _amount;
    if (amount == null || amount <= Decimal.zero) {
      setState(() => _errorMessage = 'Enter a valid amount greater than zero.');
      return;
    }

    final balance = Decimal.parse(widget.invoice.balance.wireValue);
    if (amount > balance) {
      setState(() => _errorMessage = 'Amount cannot exceed the current balance.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(paymentNotifierProvider).recordPayment(
        invoiceId: widget.invoice.id,
        method: _method,
        amount: amount.toStringAsFixed(2),
        reference: _trimOrNull(_referenceController.text),
        note: _trimOrNull(_noteController.text),
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

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final lockAmount = _lockAmount;
    final methodOptions = PaymentMethod.values
        .map((method) => AppSelectOption(value: method, label: method.label))
        .toList(growable: false);

    return AppDialog(
      key: const Key('payment_record_dialog'),
      title: 'Record payment',
      description: 'Balance due: ${widget.invoice.balance.wireValue} ${widget.invoice.currency}',
      onClose: _isSaving ? null : widget.onClose,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFormField(
            label: 'Method',
            child: AppSelect<PaymentMethod>(
              key: const Key('payment_method_field'),
              value: _method,
              options: methodOptions,
              disabled: _isSaving,
              onChanged: (value) {
                setState(() {
                  _method = value;
                  if (_lockAmount) {
                    _amount = Decimal.parse(widget.invoice.balance.wireValue);
                  }
                });
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          AppFormField(
            label: 'Amount',
            helperText: lockAmount
                ? 'Partial payments are disabled for this organization. Collect the full balance.'
                : 'Enter an amount up to the current balance.',
            child: AppMoneyField(
              key: const Key('payment_amount_field'),
              currency: widget.invoice.currency,
              value: _amount,
              disabled: _isSaving || lockAmount,
              readOnly: lockAmount,
              onValueChange: lockAmount ? null : (value) => setState(() => _amount = value),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          AppFormField(
            label: 'Reference (optional)',
            child: AppTextField(
              key: const Key('payment_reference_field'),
              controller: _referenceController,
              hintText: 'Transaction or receipt number',
              disabled: _isSaving,
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          AppFormField(
            label: 'Note (optional)',
            child: AppTextField(
              key: const Key('payment_note_field'),
              controller: _noteController,
              hintText: 'Internal note',
              maxLines: 2,
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
            key: const Key('payment_submit_button'),
            label: 'Record payment',
            loading: _isSaving,
            onPressed: _isSaving ? null : _submit,
          ),
        ],
      ),
    );
  }
}
