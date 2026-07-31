import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_review_step.dart';

/// Read-only invoice document view (`/billing/invoices/:id/review`).
class InvoiceReviewPage extends ConsumerWidget {
  const InvoiceReviewPage({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(invoiceDetailViewProvider(invoiceId));

    return detailAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (error, _) => Center(
        child: AppEmptyState(
          variant: AppEmptyStateVariant.error,
          title: 'Could not load invoice',
          description: error.toString(),
          action: EmptyStateAction(
            label: 'Retry',
            onPressed: () =>
                ref.invalidate(invoiceDetailViewProvider(invoiceId)),
          ),
        ),
      ),
      data: (view) {
        final invoice = view.invoice;
        final displayNumber = BillingFormatting.invoiceDisplayNumber(
          invoice.invoiceNumber,
          invoice.id,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPageHeader(
              title: displayNumber,
              description: [
                if (invoice.patientDisplayName?.isNotEmpty == true)
                  invoice.patientDisplayName,
                if (invoice.branchName?.isNotEmpty == true) invoice.branchName,
                if (invoice.issuedAt != null)
                  'Issued ${BillingFormatting.formatDate(invoice.issuedAt!)}',
              ].whereType<String>().join(' · '),
            ),
            const SizedBox(height: AppSpacing.space5),
            Expanded(
              child: SingleChildScrollView(
                child: VisitInvoiceReadOnlyReview(
                  invoice: invoice,
                  onBack: () => context.nav.pop(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
