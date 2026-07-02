import 'dart:async';

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
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_filters.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_list_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';

/// Searchable, filterable invoice list for daily reconciliation (V1-6 US5).
class InvoiceListPage extends ConsumerStatefulWidget {
  const InvoiceListPage({super.key});

  @override
  ConsumerState<InvoiceListPage> createState() => _InvoiceListPageState();
}

class _InvoiceListPageState extends ConsumerState<InvoiceListPage> {
  final _searchController = TextEditingController();
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
    _searchController.dispose();
    _invoiceNumberController.dispose();
    super.dispose();
  }

  void _applyFilters(InvoiceListFilters filters) {
    setState(() => _filters = filters);
    ref.read(invoiceListProvider.notifier).applyFilters(filters);
  }

  void _onPatientSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _applyFilters(_filters.copyWith(patientSearch: value, page: 1));
    });
  }

  void _onInvoiceNumberChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _applyFilters(_filters.copyWith(invoiceNumber: value, page: 1));
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
      return const _BillingPermissionDenied(message: 'You do not have permission to view invoices.');
    }

    final listAsync = ref.watch(invoiceListProvider);

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InvoiceListHeader(
            canManageInsurance: ref.watch(permissionServiceProvider).canManageInsurance(),
            onOpenInsurance: () => context.push(AppRoutes.billingInsuranceProviders),
          ),
          const SizedBox(height: SpacingTokens.md),
          _InvoiceListToolbar(
            searchController: _searchController,
            invoiceNumberController: _invoiceNumberController,
            filters: _filters,
            statusOptions: _statusOptions,
            onPatientSearchChanged: _onPatientSearchChanged,
            onInvoiceNumberChanged: _onInvoiceNumberChanged,
            onStatusToggled: (status, selected) {
              final next = List<String>.from(_filters.statuses);
              final wire = status.wireValue;
              if (selected) {
                if (!next.contains(wire)) next.add(wire);
              } else {
                next.remove(wire);
              }
              _applyFilters(_filters.copyWith(statuses: next, page: 1));
            },
            onClearFilters: () {
              _searchController.clear();
              _invoiceNumberController.clear();
              _applyFilters(const InvoiceListFilters());
            },
          ),
          const SizedBox(height: SpacingTokens.md),
          Expanded(
            child: listAsync.when(
              skipLoadingOnReload: true,
              loading: () => const Center(child: AppCircularProgress()),
              error: (error, _) => Center(child: Text('Unable to load invoices: $error')),
              data: (state) => _InvoiceListTable(
                state: state,
                onRowTap: _onRowTap,
                onPageChanged: (page) => _applyFilters(_filters.copyWith(page: page)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceListHeader extends StatelessWidget {
  const _InvoiceListHeader({required this.canManageInsurance, required this.onOpenInsurance});

  final bool canManageInsurance;
  final VoidCallback onOpenInsurance;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(Icons.receipt_long_outlined, color: colors.primary, size: 28),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Invoices', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                'Search, filter, and reconcile billing across your branches.',
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
              ),
            ],
          ),
        ),
        if (canManageInsurance)
          AppButton(
            label: 'Insurance providers',
            variant: AppButtonVariant.outline,
            icon: const Icon(Icons.health_and_safety_outlined, size: 18),
            expand: false,
            onPressed: onOpenInsurance,
          ),
      ],
    );
  }
}

class _InvoiceListToolbar extends StatelessWidget {
  const _InvoiceListToolbar({
    required this.searchController,
    required this.invoiceNumberController,
    required this.filters,
    required this.statusOptions,
    required this.onPatientSearchChanged,
    required this.onInvoiceNumberChanged,
    required this.onStatusToggled,
    required this.onClearFilters,
  });

  final TextEditingController searchController;
  final TextEditingController invoiceNumberController;
  final InvoiceListFilters filters;
  final List<InvoiceStatus> statusOptions;
  final ValueChanged<String> onPatientSearchChanged;
  final ValueChanged<String> onInvoiceNumberChanged;
  final void Function(InvoiceStatus status, bool selected) onStatusToggled;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.semanticColors.card,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: AppTextInput(
                    controller: searchController,
                    label: 'Patient search',
                    hintText: 'Search by patient name',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    onChanged: onPatientSearchChanged,
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: AppTextInput(
                    controller: invoiceNumberController,
                    label: 'Invoice number',
                    hintText: 'INV-…',
                    onChanged: onInvoiceNumberChanged,
                  ),
                ),
                if (filters.hasActiveFilters) ...[
                  const SizedBox(width: SpacingTokens.sm),
                  AppButton(label: 'Clear', variant: AppButtonVariant.ghost, expand: false, onPressed: onClearFilters),
                ],
              ],
            ),
            const SizedBox(height: SpacingTokens.sm),
            Wrap(
              spacing: SpacingTokens.xs,
              runSpacing: SpacingTokens.xs,
              children: [
                for (final status in statusOptions)
                  FilterChip(
                    label: Text(status.label),
                    selected: filters.statuses.contains(status.wireValue),
                    onSelected: (selected) => onStatusToggled(status, selected),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceListTable extends StatefulWidget {
  const _InvoiceListTable({required this.state, required this.onRowTap, required this.onPageChanged});

  final InvoiceListUiState state;
  final ValueChanged<InvoiceListItem> onRowTap;
  final ValueChanged<int> onPageChanged;

  @override
  State<_InvoiceListTable> createState() => _InvoiceListTableState();
}

class _InvoiceListTableState extends State<_InvoiceListTable> {
  var _slideDirection = 0;
  var _isPageAnimating = false;

  static final _columns = <AppDataTableColumn>[
    const AppDataTableColumn(label: 'Invoice', flex: 2),
    const AppDataTableColumn(label: 'Patient', flex: 2),
    const AppDataTableColumn(label: 'Status', flex: 2, width: 140),
    const AppDataTableColumn(label: 'Total', flex: 1, width: 100, alignment: Alignment.centerRight),
    const AppDataTableColumn(label: 'Balance', flex: 1, width: 100, alignment: Alignment.centerRight),
    const AppDataTableColumn(label: 'Date', flex: 1, width: 120),
  ];

  void _goToPage(int page) {
    if (page == widget.state.filters.page || _isPageAnimating) return;
    setState(() => _slideDirection = page > widget.state.filters.page ? 1 : -1);
    widget.onPageChanged(page);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final items = widget.state.items;
    final filters = widget.state.filters;

    if (items.isEmpty) {
      return Center(
        child: Text(
          filters.hasActiveFilters ? 'No invoices match your filters.' : 'No invoices yet.',
          style: theme.textTheme.bodyLarge?.copyWith(color: colors.mutedForeground),
        ),
      );
    }

    final hasMore = widget.state.hasMore;
    final currentPage = filters.page;

    return AppDataTable(
      columns: _columns,
      rowCount: items.length,
      bodyPageKey: currentPage,
      bodySlideDirection: _slideDirection,
      onBodyTransitionAnimating: (animating) => setState(() => _isPageAnimating = animating),
      rowBuilder: (context, index) {
        final item = items[index];
        final date = item.issuedAt ?? item.createdAt;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => widget.onRowTap(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      BillingFormatting.invoiceDisplayNumber(item.invoiceNumber, item.id),
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(flex: 2, child: Text(item.patientDisplayName ?? '—', overflow: TextOverflow.ellipsis)),
                  SizedBox(width: 140, child: InvoiceStatusBadge(status: item.status, dense: true)),
                  SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(BillingFormatting.formatMoney(Money.parse(item.displayTotal))),
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        BillingFormatting.formatMoney(item.balance),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: item.balance.isZero ? FontWeight.w400 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 120, child: Text(BillingFormatting.formatDate(date))),
                ],
              ),
            ),
          ),
        );
      },
      footer: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
        child: Row(
          children: [
            Text('Page $currentPage', style: theme.textTheme.bodySmall),
            const Spacer(),
            AppIconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous page',
              onPressed: currentPage > 1 && !_isPageAnimating ? () => _goToPage(currentPage - 1) : null,
            ),
            AppIconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next page',
              onPressed: hasMore && !_isPageAnimating ? () => _goToPage(currentPage + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _BillingPermissionDenied extends StatelessWidget {
  const _BillingPermissionDenied({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(message));
  }
}
