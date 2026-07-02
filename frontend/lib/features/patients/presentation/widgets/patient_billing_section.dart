import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';

/// Patient profile billing history section (V1-6 US5).
class PatientBillingSection extends ConsumerWidget {
  const PatientBillingSection({required this.patientId, super.key});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessInvoiceList(auth)) {
      return const SizedBox.shrink();
    }

    final invoicesAsync = ref.watch(patientInvoicesProvider(patientId));

    return AppCard(
      title: const Text('Billing'),
      description: const Text('Invoice history for this patient.'),
      child: invoicesAsync.when(
        loading: () => const Center(child: AppCircularProgress()),
        error: (error, _) => Text('Unable to load invoices: $error'),
        data: (page) {
          if (page.items.isEmpty) {
            return Text(
              'No invoices yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.semanticColors.mutedForeground),
            );
          }

          return Column(
            children: [
              for (final item in page.items) ...[
                _PatientInvoiceRow(item: item, onTap: () => _openInvoice(context, item)),
                if (item != page.items.last) const Divider(height: SpacingTokens.lg),
              ],
            ],
          );
        },
      ),
    );
  }

  void _openInvoice(BuildContext context, InvoiceListItem item) {
    if (item.status == InvoiceStatus.draft) {
      context.push(AppRoutes.billingInvoiceEdit(item.id));
      return;
    }
    context.push(AppRoutes.billingInvoiceDetail(item.id));
  }
}

class _PatientInvoiceRow extends StatelessWidget {
  const _PatientInvoiceRow({required this.item, required this.onTap});

  final InvoiceListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final date = item.issuedAt ?? item.createdAt;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SpacingTokens.xs),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      BillingFormatting.invoiceDisplayNumber(item.invoiceNumber, item.id),
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      BillingFormatting.formatDate(date),
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                    ),
                  ],
                ),
              ),
              InvoiceStatusBadge(status: item.status, dense: true),
              const SizedBox(width: SpacingTokens.md),
              Text(
                BillingFormatting.formatMoney(item.balance),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: SpacingTokens.xs),
              Icon(Icons.chevron_right, size: 20, color: colors.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}
