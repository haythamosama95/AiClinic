import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_summary_panel.dart';

/// Modal invoice summary for a completed visit.
class VisitInvoiceSummaryDialog {
  VisitInvoiceSummaryDialog._();

  static Future<void> show(BuildContext context, {required InvoiceDetail invoice}) {
    final hostContext = context;
    final canOpenDetail = AuthRouteGuard.canAccessInvoiceDetail(
      ProviderScope.containerOf(context).read(authSessionProvider),
    );

    return AppDialog.show<void>(
      context,
      title: 'Invoice summary',
      maxWidth: 480,
      size: AppDialogSize.md,
      barrierDismissible: true,
      child: VisitInvoiceSummaryPanel(invoice: invoice, expanded: true),
      footer: Builder(
        builder: (dialogContext) {
          return Row(
            children: [
              if (canOpenDetail)
                AppButton(
                  variant: AppButtonVariant.secondary,
                  leadingIcon: const Icon(Icons.open_in_new_rounded, size: 16),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    hostContext.nav.pushBillingInvoiceReview(invoice.id);
                  },
                  child: const Text('Open invoice'),
                ),
              const Spacer(),
              AppButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }
}
