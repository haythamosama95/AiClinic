import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/utils/date_format_utils.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_invoice_history_provider.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';

/// Patient profile billing history (V1-6 US5).
class PatientBillingSection extends ConsumerWidget {
  const PatientBillingSection({required this.patientId, super.key});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = patientId.trim();
    if (id.isEmpty) {
      return const SizedBox.shrink();
    }

    final permissions = ref.watch(permissionServiceProvider);
    if (!permissions.canViewInvoices()) {
      return const SizedBox.shrink();
    }

    final history = ref.watch(patientInvoiceHistoryProvider(id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Billing', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          key: const Key('patient_billing_section'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: history.loading && history.items.isEmpty
                ? const Center(
                    key: Key('patient_billing_loading'),
                    child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
                  )
                : history.error != null && history.items.isEmpty
                ? _BillingError(
                    message: history.error!,
                    onRetry: () => ref.read(patientInvoiceHistoryProvider(id).notifier).reload(),
                  )
                : _BillingBody(
                    patientId: id,
                    items: history.items,
                    hasMore: history.hasMore,
                    isLoadingMore: history.isLoadingMore,
                    loadMoreError: history.loadMoreError,
                    onLoadMore: () => ref.read(patientInvoiceHistoryProvider(id).notifier).loadMore(),
                    onOpenInvoice: (invoiceId) => context.push(AppRoutes.billingInvoiceDetail(invoiceId)),
                  ),
          ),
        ),
      ],
    );
  }
}

class _BillingError extends StatelessWidget {
  const _BillingError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('patient_billing_error'),
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

class _BillingBody extends StatelessWidget {
  const _BillingBody({
    required this.patientId,
    required this.items,
    required this.hasMore,
    required this.isLoadingMore,
    required this.loadMoreError,
    required this.onLoadMore,
    required this.onOpenInvoice,
  });

  final String patientId;
  final List<InvoiceListItem> items;
  final bool hasMore;
  final bool isLoadingMore;
  final String? loadMoreError;
  final VoidCallback onLoadMore;
  final void Function(String invoiceId) onOpenInvoice;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(
        'No invoices recorded for this patient.',
        key: const Key('patient_billing_empty'),
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...items.map(
          (item) => ListTile(
            key: Key('patient_billing_row_${item.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(item.invoiceNumber ?? 'Draft invoice'),
            subtitle: Text('${formatDate(item.issuedAt ?? item.createdAt)} · Balance ${item.balance.wireValue}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InvoiceStatusBadge(status: item.status),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => onOpenInvoice(item.id),
          ),
        ),
        if (loadMoreError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Failed to load more invoices.'),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: onLoadMore, child: const Text('Retry')),
                ],
              ),
            ),
          )
        else if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: isLoadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      key: const Key('patient_billing_load_more'),
                      onPressed: onLoadMore,
                      child: Text('Load more (${items.length} loaded)'),
                    ),
            ),
          ),
      ],
    );
  }
}
