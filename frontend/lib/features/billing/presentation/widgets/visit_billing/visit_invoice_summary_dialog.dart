import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/core/money/money_formatter.dart';

/// Modal invoice summary for a completed visit.
class VisitInvoiceSummaryDialog {
  VisitInvoiceSummaryDialog._();

  static Future<void> show(BuildContext context, {required InvoiceDetail invoice}) {
    return AppDialog.show<void>(
      context,
      title: 'Invoice summary',
      maxWidth: 480,
      size: AppDialogSize.md,
      barrierDismissible: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Invoice ${invoice.invoiceNumber}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Status: ${invoice.status.label}'),
          const SizedBox(height: 8),
          Text('Total: ${MoneyFormatter.format(invoice.subtotal, currency: invoice.currency)}'),
          if (invoice.items.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('${invoice.items.length} line item(s)', style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
      footer: Builder(
        builder: (dialogContext) => Row(
          children: [
            const Spacer(),
            AppButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
