import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';

/// Confirms voiding an issued or partially paid invoice with a mandatory reason.
Future<bool> showVoidInvoiceDialog({
  required BuildContext context,
  required WidgetRef ref,
  required InvoiceDetail invoice,
}) {
  return showAppDialog<bool>(
    context,
    size: AppDialogSize.sm,
    barrierDismissible: false,
    semanticLabel: 'Void invoice',
    builder: (dialogContext, close) {
      return _VoidInvoiceDialogContent(
        invoice: invoice,
        onClose: () => close(false),
        onVoided: () => close(true),
      );
    },
  ).then((value) => value ?? false);
}

class _VoidInvoiceDialogContent extends ConsumerStatefulWidget {
  const _VoidInvoiceDialogContent({
    required this.invoice,
    required this.onClose,
    required this.onVoided,
  });

  final InvoiceDetail invoice;
  final VoidCallback onClose;
  final VoidCallback onVoided;

  @override
  ConsumerState<_VoidInvoiceDialogContent> createState() => _VoidInvoiceDialogContentState();
}

class _VoidInvoiceDialogContentState extends ConsumerState<_VoidInvoiceDialogContent> {
  final _reasonController = TextEditingController();
  var _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _errorMessage = 'Enter a reason before voiding.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(invoiceRepositoryProvider).voidInvoice(
        invoiceId: widget.invoice.id,
        expectedUpdatedAt: widget.invoice.updatedAt,
        reason: reason,
      );
      ref.invalidate(invoiceDetailViewProvider(widget.invoice.id));
      if (!mounted) {
        return;
      }
      widget.onVoided();
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
    final number = widget.invoice.invoiceNumber ?? widget.invoice.id;

    return AppDialog(
      key: const Key('void_invoice_dialog'),
      title: 'Void invoice $number?',
      description:
          'Voiding locks this invoice from further changes. A reason is required for the audit trail.',
      onClose: _isSaving ? null : widget.onClose,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFormField(
            label: 'Reason',
            child: AppTextField(
              key: const Key('void_reason_field'),
              controller: _reasonController,
              hintText: 'Why is this invoice being voided?',
              maxLines: 3,
              disabled: _isSaving,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.s3),
            AppAlert(
              variant: AppAlertVariant.danger,
              title: _errorMessage!,
            ),
          ],
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            key: const Key('void_invoice_cancel_button'),
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            disabled: _isSaving,
            onPressed: widget.onClose,
          ),
          const SizedBox(width: AppSpacing.s2),
          AppButton(
            key: const Key('void_invoice_confirm_button'),
            label: 'Void invoice',
            variant: AppButtonVariant.danger,
            loading: _isSaving,
            onPressed: _isSaving ? null : _submit,
          ),
        ],
      ),
    );
  }
}
