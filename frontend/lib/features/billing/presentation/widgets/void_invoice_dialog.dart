import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';

/// Collects a mandatory void reason; mutation is handled by the caller (V1-6 US6).
class VoidInvoiceDialog extends StatefulWidget {
  const VoidInvoiceDialog({
    required this.displayNumber,
    required this.patientName,
    super.key,
  });

  final String displayNumber;
  final String patientName;

  /// Returns the trimmed reason when confirmed, or `null` when dismissed.
  static Future<String?> show(BuildContext context, {required InvoiceDetail invoice}) {
    final displayNumber = BillingFormatting.invoiceDisplayNumber(invoice.invoiceNumber, invoice.id);
    final patientName = invoice.patientDisplayName?.trim().isNotEmpty == true
        ? invoice.patientDisplayName!.trim()
        : 'Unknown patient';

    return AppDialog.show<String?>(
      context,
      title: 'Void invoice?',
      description: 'Void $displayNumber for $patientName? This action cannot be undone.',
      size: AppDialogSize.sm,
      child: VoidInvoiceDialog(displayNumber: displayNumber, patientName: patientName),
    );
  }

  /// Returns the trimmed reason when confirmed, or `null` when dismissed.
  static Future<String?> showForRow(BuildContext context, {required InvoiceListItem row}) {
    final displayNumber = BillingFormatting.invoiceDisplayNumber(row.invoiceNumber, row.id);
    final patientName = row.patientDisplayName?.trim().isNotEmpty == true
        ? row.patientDisplayName!.trim()
        : 'Unknown patient';

    return AppDialog.show<String?>(
      context,
      title: 'Void invoice?',
      description: 'Void $displayNumber for $patientName? This action cannot be undone.',
      size: AppDialogSize.sm,
      child: VoidInvoiceDialog(displayNumber: displayNumber, patientName: patientName),
    );
  }

  @override
  State<VoidInvoiceDialog> createState() => _VoidInvoiceDialogState();
}

class _VoidInvoiceDialogState extends State<VoidInvoiceDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _confirm() {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reasonController.text.trim();
    final canConfirm = reason.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppFormField(
          id: 'void-reason',
          label: 'Reason',
          child: AppTextarea(
            controller: _reasonController,
            placeholder: 'e.g. Duplicate invoice created in error',
            rows: 3,
            maxLength: 2000,
            showCounter: true,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Keep invoice'),
            ),
            const SizedBox(width: AppSpacing.space2),
            AppButton(
              variant: AppButtonVariant.danger,
              onPressed: canConfirm ? _confirm : null,
              child: const Text('Void invoice'),
            ),
          ],
        ),
      ],
    );
  }
}
