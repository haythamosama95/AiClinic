import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/utils/date_format_utils.dart';
import 'package:ai_clinic/core/widgets/app_data_table.dart';
import 'package:ai_clinic/core/widgets/skeleton_list.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/auth/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_list_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/billing_access_denied_view.dart';

/// Invoice list with filters and pagination (V1-6 US5).
class InvoiceListPage extends ConsumerWidget {
  const InvoiceListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);
    if (!permissions.canViewInvoices()) {
      return const BillingAccessDeniedView(title: 'Invoices', message: 'You do not have permission to view invoices.');
    }

    final listState = ref.watch(invoiceListProvider);
    final branchesAsync = ref.watch(staffAssignableBranchesProvider);
    final branchIds = ref.watch(authSessionProvider).context?.branchIds ?? const <String>[];
    final showBranchFilter = branchIds.length > 1;

    return Scaffold(
      key: const Key('invoice_list_page'),
      appBar: AppBar(
        title: const Text('Invoices'),
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.nav.goHome(),
        ),
        actions: [
          IconButton(
            key: const Key('invoice_list_refresh_button'),
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(invoiceListProvider.notifier).reload(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InvoiceListFilterBar(showBranchFilter: showBranchFilter, branchesAsync: branchesAsync),
          Expanded(
            child: listState.loading && listState.items.isEmpty
                ? const SkeletonList()
                : listState.error != null && listState.items.isEmpty
                ? _InvoiceListError(
                    message: listState.error!,
                    onRetry: () => ref.read(invoiceListProvider.notifier).reload(),
                  )
                : _InvoiceListBody(
                    items: listState.items,
                    showBranchColumn: showBranchFilter,
                    hasMore: listState.hasMore,
                    isLoadingMore: listState.isLoadingMore,
                    loadMoreError: listState.loadMoreError,
                    onLoadMore: () => ref.read(invoiceListProvider.notifier).loadMore(),
                    onOpenInvoice: (id) => context.push(AppRoutes.billingInvoiceDetail(id)),
                  ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceListFilterBar extends ConsumerWidget {
  const _InvoiceListFilterBar({required this.showBranchFilter, required this.branchesAsync});

  final bool showBranchFilter;
  final AsyncValue<List<BranchSummary>> branchesAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(invoiceListProvider.notifier);
    final filters = ref.watch(invoiceListProvider).filters;
    final theme = Theme.of(context);

    return Material(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<InvoiceStatus?>(
                  key: const Key('invoice_list_filter_status'),
                  isExpanded: true,
                  value: filters.status,
                  decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All statuses')),
                    for (final status in InvoiceStatus.values)
                      DropdownMenuItem(value: status, child: Text(status.label)),
                  ],
                  onChanged: notifier.setStatusFilter,
                ),
              ),
              if (showBranchFilter)
                SizedBox(
                  width: 200,
                  child: branchesAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (branches) => DropdownButtonFormField<String?>(
                      key: const Key('invoice_list_filter_branch'),
                      isExpanded: true,
                      value: filters.branchId,
                      decoration: const InputDecoration(labelText: 'Branch', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All branches')),
                        for (final branch in branches) DropdownMenuItem(value: branch.id, child: Text(branch.name)),
                      ],
                      onChanged: notifier.setBranchFilter,
                    ),
                  ),
                ),
              SizedBox(
                width: 220,
                child: TextField(
                  key: const Key('invoice_list_patient_search'),
                  decoration: const InputDecoration(
                    labelText: 'Patient search',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: notifier.setPatientSearch,
                ),
              ),
              SizedBox(
                width: 200,
                child: TextField(
                  key: const Key('invoice_list_filter_invoice_number'),
                  decoration: const InputDecoration(
                    labelText: 'Invoice number',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: notifier.setInvoiceNumberFilter,
                ),
              ),
              OutlinedButton.icon(
                key: const Key('invoice_list_date_range_button'),
                onPressed: () => _pickDateRange(context, ref),
                icon: const Icon(Icons.date_range_outlined),
                label: Text(_dateRangeLabel(filters.dateFrom, filters.dateTo)),
              ),
              if (filters.dateFrom != null || filters.dateTo != null)
                TextButton(
                  onPressed: () => notifier.setDateRange(from: null, to: null),
                  child: const Text('Clear dates'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _dateRangeLabel(DateTime? from, DateTime? to) {
    if (from == null && to == null) {
      return 'Date range';
    }
    if (from != null && to != null) {
      return '${formatDate(from)} – ${formatDate(to)}';
    }
    if (from != null) {
      return 'From ${formatDate(from)}';
    }
    return 'Until ${formatDate(to)}';
  }

  Future<void> _pickDateRange(BuildContext context, WidgetRef ref) async {
    final filters = ref.read(invoiceListProvider).filters;
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: filters.dateFrom != null && filters.dateTo != null
          ? DateTimeRange(start: filters.dateFrom!, end: filters.dateTo!)
          : null,
    );
    if (range == null || !context.mounted) {
      return;
    }
    ref.read(invoiceListProvider.notifier).setDateRange(from: range.start, to: range.end);
  }
}

class _InvoiceListError extends StatelessWidget {
  const _InvoiceListError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _InvoiceListBody extends StatelessWidget {
  const _InvoiceListBody({
    required this.items,
    required this.showBranchColumn,
    required this.hasMore,
    required this.isLoadingMore,
    required this.loadMoreError,
    required this.onLoadMore,
    required this.onOpenInvoice,
  });

  final List<InvoiceListItem> items;
  final bool showBranchColumn;
  final bool hasMore;
  final bool isLoadingMore;
  final String? loadMoreError;
  final VoidCallback onLoadMore;
  final void Function(String invoiceId) onOpenInvoice;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        key: Key('invoice_list_empty'),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No invoices match your filters.', textAlign: TextAlign.center),
        ),
      );
    }

    final columns = <AppDataColumn>[
      const AppDataColumn(label: 'Invoice #'),
      const AppDataColumn(label: 'Patient'),
      const AppDataColumn(label: 'Date'),
      const AppDataColumn(label: 'Status'),
      if (showBranchColumn) const AppDataColumn(label: 'Branch'),
      const AppDataColumn(label: 'Total', numeric: true),
      const AppDataColumn(label: 'Paid', numeric: true),
      const AppDataColumn(label: 'Balance', numeric: true),
    ];

    final rows = [
      for (final item in items)
        [
          item.invoiceNumber ?? 'Draft',
          item.patientDisplayName ?? '—',
          formatDate(item.issuedAt ?? item.createdAt),
          item.status.label,
          if (showBranchColumn) item.branchCode ?? '—',
          item.displayTotal,
          item.paidAmount,
          item.balance,
        ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: AppDataTable(
            key: const Key('invoice_list_table'),
            columns: columns,
            rows: rows,
            emptyMessage: 'No invoices match your filters.',
            onRowTap: (index) => onOpenInvoice(items[index].id),
          ),
        ),
        if (loadMoreError != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(loadMoreError!),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: onLoadMore, child: const Text('Retry')),
                ],
              ),
            ),
          )
        else if (hasMore)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: isLoadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      key: const Key('invoice_list_load_more'),
                      onPressed: onLoadMore,
                      child: Text('Load more (${items.length} loaded)'),
                    ),
            ),
          ),
      ],
    );
  }
}
