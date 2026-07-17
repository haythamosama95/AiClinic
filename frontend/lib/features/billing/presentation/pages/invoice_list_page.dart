import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/components/app_pagination.dart';
import 'package:ai_clinic/core/ui/components/app_search_input.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_filters.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_list_notifier.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/invoice_status_badge.dart';

/// Invoice ledger list (`/billing/invoices`).
class InvoiceListPage extends ConsumerStatefulWidget {
  const InvoiceListPage({super.key});

  @override
  ConsumerState<InvoiceListPage> createState() => _InvoiceListPageState();
}

class _InvoiceListPageState extends ConsumerState<InvoiceListPage> with SingleTickerProviderStateMixin {
  static const _defaultFilters = InvoiceListFilters(pageSize: 20);
  static const _tabularFigures = [FontFeature.tabularFigures()];

  late final AnimationController _enterController;
  late final Animation<double> _enterAnimation;
  final _searchController = TextEditingController();
  var _searchApplied = '';

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _enterAnimation = CurvedAnimation(parent: _enterController, curve: AppMotion.outCurve);
    _searchController.addListener(() => _onSearch(_searchController.text));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(invoiceListProvider.notifier).reload();
        _enterController.forward();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _enterController.dispose();
    super.dispose();
  }

  void _applyFilters(InvoiceListFilters filters) {
    ref.read(invoiceListProvider.notifier).applyFilters(filters);
  }

  void _onSearch(String value) {
    final trimmed = value.trim();
    if (trimmed == _searchApplied) {
      return;
    }
    _searchApplied = trimmed;
    final current = ref.read(invoiceListProvider).value?.filters ?? _defaultFilters;
    _applyFilters(current.copyWith(patientSearch: trimmed, page: 1));
  }

  void _toggleStatus(InvoiceListFilters current, InvoiceStatus status) {
    final statuses = List<String>.from(current.statuses);
    final wire = status.wireValue;
    if (statuses.contains(wire)) {
      statuses.remove(wire);
    } else {
      statuses.add(wire);
    }
    _applyFilters(current.copyWith(statuses: statuses, page: 1));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final listAsync = ref.watch(invoiceListProvider);

    return FadeTransition(
      opacity: _enterAnimation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPageHeader(title: 'Invoices', description: 'Branch ledger of issued charges, payments, and balances.'),
          const SizedBox(height: AppSpacing.space5),
          Row(
            children: [
              Expanded(
                child: AppSearchInput(controller: _searchController, placeholder: 'Search by patient name'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          listAsync.when(
            loading: () => const Expanded(child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            error: (error, _) => Expanded(
              child: AppEmptyState(
                variant: AppEmptyStateVariant.error,
                title: 'Could not load invoices',
                description: error.toString(),
                action: EmptyStateAction(label: 'Retry', onPressed: () => ref.invalidate(invoiceListProvider)),
              ),
            ),
            data: (state) {
              final filters = state.filters;
              return Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusFilterRow(
                      filters: filters,
                      onToggle: (status) => _toggleStatus(filters, status),
                      onClear: () => _applyFilters(filters.copyWith(statuses: const [], page: 1)),
                    ),
                    const SizedBox(height: AppSpacing.space4),
                    Expanded(
                      child: state.isEmpty
                          ? AppEmptyState(
                              variant: filters.hasActiveFilters
                                  ? AppEmptyStateVariant.noResults
                                  : AppEmptyStateVariant.firstRun,
                              title: filters.hasActiveFilters ? 'No invoices match' : 'No invoices yet',
                              description: filters.hasActiveFilters
                                  ? 'Try clearing filters or a different search.'
                                  : 'Invoices appear here after visits are finalized with billing.',
                            )
                          : _InvoiceLedgerList(
                              items: state.items,
                              onOpen: (item) => context.nav.pushBillingInvoiceDetail(item.id),
                            ),
                    ),
                    if (!state.isEmpty) ...[
                      const SizedBox(height: AppSpacing.space4),
                      AppPagination(
                        page: filters.page,
                        pageSize: filters.pageSize,
                        total: state.estimatedTotal,
                        onPageChange: (page) => _applyFilters(filters.copyWith(page: page)),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatusFilterRow extends StatelessWidget {
  const _StatusFilterRow({required this.filters, required this.onToggle, required this.onClear});

  final InvoiceListFilters filters;
  final ValueChanged<InvoiceStatus> onToggle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final active = filters.statuses.toSet();

    return Wrap(
      spacing: AppSpacing.space2,
      runSpacing: AppSpacing.space2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Status', style: AppTypography.caption(context).copyWith(color: colors.textTertiary)),
        for (final status in InvoiceStatus.values)
          AppChip(
            selectable: true,
            selected: active.contains(status.wireValue),
            onSelect: () => onToggle(status),
            child: Text(status.label),
          ),
        if (filters.statuses.isNotEmpty)
          AppButton(variant: AppButtonVariant.ghost, onPressed: onClear, child: const Text('Clear')),
      ],
    );
  }
}

class _InvoiceLedgerList extends StatelessWidget {
  const _InvoiceLedgerList({required this.items, required this.onOpen});

  final List<InvoiceListItem> items;
  final ValueChanged<InvoiceListItem> onOpen;

  static const _tabularFigures = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = Theme.of(context).extension<AppElevation>();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        border: Border.all(color: colors.borderSubtle),
        boxShadow: elevation?.shadows1 ?? AppElevation.level1,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        child: ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: colors.borderSubtle),
          itemBuilder: (context, index) {
            final item = items[index];
            return _InvoiceLedgerRow(item: item, onOpen: () => onOpen(item));
          },
        ),
      ),
    );
  }
}

class _InvoiceLedgerRow extends StatelessWidget {
  const _InvoiceLedgerRow({required this.item, required this.onOpen});

  final InvoiceListItem item;
  final VoidCallback onOpen;

  static const _tabularFigures = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final stripe = _statusStripeColor(item.status, colors);
    final displayNumber = BillingFormatting.invoiceDisplayNumber(item.invoiceNumber, item.id);
    final netTotal = item.subtotal - item.discountAmount;
    final issuedAt = item.issuedAt ?? item.createdAt;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: stripe),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5, vertical: AppSpacing.space4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayNumber,
                              style: AppTypography.mono(context).copyWith(
                                color: colors.textPrimary,
                                letterSpacing: 0.06 * 13,
                                fontFeatures: _tabularFigures,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.space1),
                            Text(
                              item.patientDisplayName?.trim().isNotEmpty == true ? item.patientDisplayName! : 'Patient',
                              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          BillingFormatting.formatDate(issuedAt),
                          style: AppTypography.bodySm(
                            context,
                          ).copyWith(color: colors.textSecondary, fontFeatures: _tabularFigures),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          BillingFormatting.formatMoney(netTotal, currency: item.currency),
                          textAlign: TextAlign.end,
                          style: AppTypography.bodyStrong(context).copyWith(fontFeatures: _tabularFigures),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.space4),
                      InvoiceStatusBadge(status: item.status),
                      const SizedBox(width: AppSpacing.space2),
                      Icon(Icons.chevron_right, color: colors.iconMuted, size: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusStripeColor(InvoiceStatus status, AppSemanticColors colors) {
    return switch (status) {
      InvoiceStatus.draft => colors.textTertiary,
      InvoiceStatus.issued => colors.statusInfoFg,
      InvoiceStatus.partiallyPaid => colors.statusWarningFg,
      InvoiceStatus.paid => colors.statusSuccessFg,
      InvoiceStatus.voided => colors.statusDangerFg,
    };
  }
}
