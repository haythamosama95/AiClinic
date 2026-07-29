import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/application/billing_rpc_messages.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';

/// Confirms voiding an issued or partially paid invoice.
class VoidInvoiceDialog {
  VoidInvoiceDialog._();

  static Future<bool> show(
    BuildContext context, {
    required InvoiceDetail invoice,
  }) async {
    final result = await AppDialog.show<bool>(
      context,
      title: 'Void invoice',
      maxWidth: 440,
      size: AppDialogSize.md,
      child: _VoidInvoiceDialogContent(invoice: invoice),
    );
    return result ?? false;
  }
}

class _VoidInvoiceDialogContent extends ConsumerStatefulWidget {
  const _VoidInvoiceDialogContent({required this.invoice});

  final InvoiceDetail invoice;

  @override
  ConsumerState<_VoidInvoiceDialogContent> createState() =>
      _VoidInvoiceDialogContentState();
}

class _VoidInvoiceDialogContentState
    extends ConsumerState<_VoidInvoiceDialogContent> {
  final _reasonController = TextEditingController();
  var _submitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit(BuildContext dialogContext) async {
    if (_submitting || _reasonController.text.trim().isEmpty) {
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(invoiceRepositoryProvider)
          .voidInvoice(
            invoiceId: widget.invoice.id,
            expectedUpdatedAt: widget.invoice.updatedAt,
            reason: _reasonController.text.trim(),
          );
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop(true);
      }
    } on RpcFailure catch (error) {
      if (mounted) {
        appToast(
          context,
          AppToastInput(
            message: billingMessageForRpc(error),
            variant: AppToastVariant.danger,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        appToast(
          context,
          const AppToastInput(
            message: 'Could not void the invoice. Please try again.',
            variant: AppToastVariant.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'This cannot be undone. Payments must be refunded before voiding a paid invoice.',
          style: AppTypography.bodySm(
            context,
          ).copyWith(color: context.appColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space4),
        AppFormField(
          id: 'void-reason',
          label: 'Reason',
          child: AppTextarea(
            controller: _reasonController,
            placeholder: 'Why is this invoice being voided?',
            rows: 3,
            disabled: _submitting,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        Row(
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              onPressed: _submitting
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            const Spacer(),
            AppButton(
              variant: AppButtonVariant.danger,
              loading: _submitting,
              onPressed: _submitting || _reasonController.text.trim().isEmpty
                  ? null
                  : () => _submit(context),
              child: const Text('Void invoice'),
            ),
          ],
        ),
      ],
    );
  }
}
