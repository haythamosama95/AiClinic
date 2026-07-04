import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_filters.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_list_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_list_table.dart';

/// Searchable, filterable invoice list for daily reconciliation (V1-6 US5).
class InvoiceListPage extends ConsumerStatefulWidget {
  const InvoiceListPage({super.key});

  @override
  ConsumerState<InvoiceListPage> createState() => _InvoiceListPageState();
}

class _InvoiceListPageState extends ConsumerState<InvoiceListPage> {
  final _patientSearchController = TextEditingController();
  final _invoiceNumberController = TextEditingController();
  Timer? _searchDebounce;
  InvoiceListFilters _filters = const InvoiceListFilters();

  static const _statusOptions = <InvoiceStatus>[
    InvoiceStatus.draft,
    InvoiceStatus.issued,
    InvoiceStatus.partiallyPaid,
    InvoiceStatus.paid,
    InvoiceStatus.voided,
  ];

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _patientSearchController.dispose();
    _invoiceNumberController.dispose();
    super.dispose();
  }

  void _applyFilters(InvoiceListFilters filters) {
    setState(() => _filters = filters);
    ref.read(invoiceListProvider.notifier).applyFilters(filters);
  }

  void _debouncedApply(void Function() mutate) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      mutate();
    });
  }

  void _onRowTap(InvoiceListItem item) {
    if (item.status == InvoiceStatus.draft) {
      context.push(AppRoutes.billingInvoiceEdit(item.id));
      return;
    }
    context.push(AppRoutes.billingInvoiceDetail(item.id));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessInvoiceList(auth)) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Invoices',
        description: 'You do not have permission to view invoices.',
      );
    }

    final listAsync = ref.watch(invoiceListProvider);
    final canManageInsurance = ref.watch(permissionServiceProvider).canManageInsurance();

    return listAsync.when(
      skipLoadingOnReload: true,
      loading: () => _buildShell(context, canManageInsurance: canManageInsurance, body: _buildTable(loading: true)),
      error: (error, _) => _buildShell(
        context,
        canManageInsurance: canManageInsurance,
        body: _buildTable(error: error, onRetry: () => ref.read(invoiceListProvider.notifier).reload()),
      ),
      data: (state) => _buildShell(
        context,
        canManageInsurance: canManageInsurance,
        state: state,
        body: _buildTable(
          items: state.items,
          hasMore: state.hasMore,
          filteredEmpty: state.isEmpty && _filters.hasActiveFilters,
          emptyFirstRun: state.isEmpty && !_filters.hasActiveFilters,
          onRowTap: _onRowTap,
          onRetry: () => ref.read(invoiceListProvider.notifier).reload(),
        ),
      ),
    );
  }

  Widget _buildShell(
    BuildContext context, {
    required bool canManageInsurance,
    required Widget body,
    InvoiceListUiState? state,
  }) {
    final filters = state?.filters ?? _filters;
    final itemCount = state?.items.length ?? 0;
    final pageCount = state == null
        ? 1
        : (state.hasMore ? filters.page + 1 : filters.page).clamp(1, 1 << 30);

    return ListIndexPattern(
      title: 'Invoices',
      description: 'Search, filter, and reconcile billing across your branches.',
      headerActions: canManageInsurance
          ? AppButton(
              label: 'Insurance providers',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              leadingIcon: LucideIcons.shield,
              onPressed: () => context.push(AppRoutes.billingInsuranceProviders),
            )
          : null,
      toolbarStart: SizedBox(
        width: 260,
        child: AppSearchField(
          controller: _patientSearchController,
          hintText: 'Search by patient name…',
          onValueChange: (value) => _debouncedApply(
            () => _applyFilters(filters.copyWith(patientSearch: value, page: 1)),
          ),
        ),
      ),
      toolbarCenter: SizedBox(
        width: 200,
        child: AppTextField(
          controller: _invoiceNumberController,
          hintText: 'Invoice number',
          onChanged: (value) => _debouncedApply(
            () => _applyFilters(filters.copyWith(invoiceNumber: value, page: 1)),
          ),
        ),
      ),
      toolbarEnd: filters.hasActiveFilters
          ? AppButton(
              label: 'Clear filters',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: () {
                _patientSearchController.clear();
                _invoiceNumberController.clear();
                _applyFilters(const InvoiceListFilters());
              },
            )
          : null,
      filterChips: Wrap(
        spacing: AppSpacing.s2,
        runSpacing: AppSpacing.s2,
        children: [
          for (final status in _statusOptions)
            AppChip(
              selectable: true,
              selected: filters.statuses.contains(status.wireValue),
              onSelect: () {
                final next = List<String>.from(filters.statuses);
                final wire = status.wireValue;
                if (next.contains(wire)) {
                  next.remove(wire);
                } else {
                  next.add(wire);
                }
                _applyFilters(filters.copyWith(statuses: next, page: 1));
              },
              child: Text(status.label),
            ),
        ],
      ),
      table: body,
      page: filters.page,
      pageCount: pageCount,
      onPageChanged: (page) => _applyFilters(filters.copyWith(page: page)),
      paginationLabel: state == null ? 'Invoices' : 'Showing $itemCount invoices',
    );
  }

  Widget _buildTable({
    List<InvoiceListItem> items = const [],
    bool hasMore = false,
    bool loading = false,
    Object? error,
    bool filteredEmpty = false,
    bool emptyFirstRun = false,
    ValueChanged<InvoiceListItem>? onRowTap,
    VoidCallback? onRetry,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useCards = constraints.maxWidth < AppBreakpoints.md;

        if (useCards) {
          if (loading) {
            return const Center(child: AppSpinner());
          }
          if (error != null) {
            return AppErrorState(message: error.toString(), onRetry: onRetry);
          }
          if (emptyFirstRun) {
            return const AppEmptyState(
              variant: AppEmptyStateVariant.firstRun,
              title: 'No invoices yet',
              description: 'Invoices will appear here once visits are billed.',
            );
          }
          if (filteredEmpty) {
            return const AppEmptyState(
              variant: AppEmptyStateVariant.noResults,
              title: 'No invoices match your filters',
              description: 'Try adjusting your search or status filters.',
            );
          }
          return InvoiceListCards(items: items, onItemTap: onRowTap ?? (_) {});
        }

        return AppTable<InvoiceListItem>(
          columns: buildInvoiceTableColumns(context),
          rowId: (item) => item.id,
          data: items,
          stickyFirstColumn: true,
          loading: loading,
          error: error,
          onRetry: onRetry,
          filteredEmpty: filteredEmpty,
          onRowTap: onRowTap,
          emptyState: const AppEmptyState(
            variant: AppEmptyStateVariant.firstRun,
            title: 'No invoices yet',
            description: 'Invoices will appear here once visits are billed.',
          ),
          filteredEmptyState: const AppEmptyState(
            variant: AppEmptyStateVariant.noResults,
            title: 'No invoices match your filters',
            description: 'Try adjusting your search or status filters.',
          ),
          semanticLabel: 'Invoices',
          footer: hasMore ? const Text('More results available on the next page.') : null,
        );
      },
    );
  }
}
