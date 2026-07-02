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
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/service_catalog/presentation/models/service_list_filters.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_catalog_list_notifier.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/copy_configuration_dialog.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/create_service_modal.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';

/// Paginated service catalog management list (015 US6).
class ServiceCatalogListPage extends ConsumerStatefulWidget {
  const ServiceCatalogListPage({super.key});

  @override
  ConsumerState<ServiceCatalogListPage> createState() => _ServiceCatalogListPageState();
}

class _ServiceCatalogListPageState extends ConsumerState<ServiceCatalogListPage> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  ServiceListFilters _filters = const ServiceListFilters();

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters(ServiceListFilters filters) {
    setState(() => _filters = filters);
    ref.read(serviceCatalogListProvider.notifier).applyFilters(filters);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _applyFilters(_filters.copyWith(query: value, page: 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessServiceCatalogList(auth)) {
      return const Scaffold(body: Center(child: Text('You do not have permission to view the service catalog.')));
    }

    final listAsync = ref.watch(serviceCatalogListProvider);
    final branchesAsync = ref.watch(clinicSetupBranchesProvider);
    final canManage = ref.watch(permissionServiceProvider).canManageServices();

    return Scaffold(
      backgroundColor: context.semanticColors.background,
      body: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 720;
                final title = Expanded(
                  child: Text(
                    'Service catalog',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                );

                final actions = <Widget>[
                  if (canManage) ...[
                    AppButton(
                      label: 'Copy branch config',
                      variant: AppButtonVariant.outline,
                      expand: false,
                      onPressed: () async {
                        final branches = await ref.read(clinicSetupBranchesProvider.future);
                        if (!context.mounted) {
                          return;
                        }
                        final copied = await CopyConfigurationDialog.show(context, branches: branches);
                        if (copied == true && context.mounted) {
                          ref.invalidate(serviceCatalogListProvider);
                          AppToast.success(context, message: 'Branch configuration copied.');
                        }
                      },
                    ),
                    const SizedBox(width: SpacingTokens.sm),
                    AppButton(
                      label: 'Add service',
                      icon: const Icon(Icons.add, size: 18),
                      expand: false,
                      onPressed: () async {
                        final created = await CreateServiceModal.show(context);
                        if (created == true && context.mounted) {
                          ref.invalidate(serviceCatalogListProvider);
                        }
                      },
                    ),
                  ],
                ];

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          AppIconButton(
                            icon: const Icon(Icons.arrow_back),
                            tooltip: 'Back',
                            onPressed: () => context.pop(),
                          ),
                          const SizedBox(width: SpacingTokens.sm),
                          title,
                        ],
                      ),
                      if (canManage) ...[
                        const SizedBox(height: SpacingTokens.sm),
                        Wrap(spacing: SpacingTokens.sm, runSpacing: SpacingTokens.sm, children: actions),
                      ],
                    ],
                  );
                }

                return Row(
                  children: [
                    AppIconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.pop()),
                    const SizedBox(width: SpacingTokens.sm),
                    title,
                    ...actions,
                  ],
                );
              },
            ),
            const SizedBox(height: SpacingTokens.md),
            _ServiceCatalogListToolbar(
              searchController: _searchController,
              filters: _filters,
              branchesAsync: branchesAsync,
              onSearchChanged: _onSearchChanged,
              onStatusChanged: (status) => _applyFilters(_filters.copyWith(globalStatus: status, page: 1)),
              onBranchChanged: (branchId) {
                if (branchId == null) {
                  _applyFilters(_filters.copyWith(clearBranchId: true, page: 1));
                  return;
                }
                _applyFilters(_filters.copyWith(branchId: branchId, page: 1));
              },
              onClearFilters: () {
                _searchController.clear();
                _applyFilters(const ServiceListFilters());
              },
            ),
            const SizedBox(height: SpacingTokens.md),
            Expanded(
              child: listAsync.when(
                loading: () => const Center(child: AppCircularProgress()),
                error: (error, _) => Center(child: Text('Unable to load services: $error')),
                data: (state) {
                  if (state.isEmpty) {
                    return const Center(child: Text('No services match your filters.'));
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ListView.separated(
                          itemCount: state.items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: SpacingTokens.sm),
                          itemBuilder: (context, index) {
                            final item = state.items[index];
                            return _ServiceCatalogListRow(
                              item: item,
                              showBranchSummary: _filters.branchId != null,
                              onTap: canManage
                                  ? () => context.push(AppRoutes.settingsServiceEdit(item.serviceId))
                                  : null,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: SpacingTokens.md),
                      _ServiceCatalogPagination(
                        filters: state.filters,
                        total: state.total,
                        onPageChanged: (page) => _applyFilters(state.filters.copyWith(page: page)),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceCatalogListToolbar extends StatelessWidget {
  const _ServiceCatalogListToolbar({
    required this.searchController,
    required this.filters,
    required this.branchesAsync,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onBranchChanged,
    required this.onClearFilters,
  });

  final TextEditingController searchController;
  final ServiceListFilters filters;
  final AsyncValue<List<BranchListItem>> branchesAsync;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<GlobalStatus?> onStatusChanged;
  final ValueChanged<String?> onBranchChanged;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final branchOptions = branchesAsync.maybeWhen(
      data: (branches) => [
        const AppSelectOption<String?>(value: null, label: 'All branches'),
        for (final branch in branches) AppSelectOption<String?>(value: branch.id, label: branch.name),
      ],
      orElse: () => const [AppSelectOption<String?>(value: null, label: 'All branches')],
    );

    return Wrap(
      spacing: SpacingTokens.md,
      runSpacing: SpacingTokens.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: AppTextField(
            controller: searchController,
            label: 'Search',
            hintText: 'Service name',
            onChanged: onSearchChanged,
          ),
        ),
        AppSelectTileGroup<GlobalStatus?>(
          label: 'Status',
          mode: AppSelectGroupMode.radio,
          options: const [
            AppSelectOption(value: null, label: 'All'),
            AppSelectOption(value: GlobalStatus.active, label: 'Active'),
            AppSelectOption(value: GlobalStatus.inactive, label: 'Inactive'),
          ],
          values: {filters.globalStatus},
          onChanged: (values) => onStatusChanged(values.isEmpty ? null : values.first),
        ),
        AppSelectTileGroup<String?>(
          label: 'Branch',
          mode: AppSelectGroupMode.radio,
          options: branchOptions,
          values: {filters.branchId},
          onChanged: (values) => onBranchChanged(values.isEmpty ? null : values.first),
        ),
        if (filters.hasActiveFilters)
          AppButton(label: 'Clear filters', variant: AppButtonVariant.ghost, expand: false, onPressed: onClearFilters),
      ],
    );
  }
}

class _ServiceCatalogListRow extends StatelessWidget {
  const _ServiceCatalogListRow({required this.item, required this.showBranchSummary, this.onTap});

  final ServiceListItem item;
  final bool showBranchSummary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = item.branchSummary;

    return Material(
      color: context.semanticColors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(SpacingTokens.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: SpacingTokens.xs),
                    Text(
                      'Default ${BillingFormatting.formatMoney(item.defaultPrice)} · ${item.assignedBranchCount} branch(es) · ${item.globalStatus.name}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (showBranchSummary && summary != null) ...[
                      const SizedBox(height: SpacingTokens.xs),
                      Text(
                        'Branch price ${BillingFormatting.formatMoney(summary.effectivePrice)} · ${summary.status}${summary.onPromotion ? ' · on promotion' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              _GlobalStatusChip(status: item.globalStatus),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlobalStatusChip extends StatelessWidget {
  const _GlobalStatusChip({required this.status});

  final GlobalStatus status;

  @override
  Widget build(BuildContext context) {
    final isActive = status == GlobalStatus.active;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.xs),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.withValues(alpha: 0.12) : Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(isActive ? 'Active' : 'Inactive', style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _ServiceCatalogPagination extends StatelessWidget {
  const _ServiceCatalogPagination({required this.filters, required this.total, required this.onPageChanged});

  final ServiceListFilters filters;
  final int total;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final totalPages = total == 0 ? 1 : (total / filters.pageSize).ceil();
    final canGoBack = filters.page > 1;
    final canGoForward = filters.page < totalPages;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Page ${filters.page} of $totalPages · $total total'),
        Row(
          children: [
            AppButton(
              label: 'Previous',
              variant: AppButtonVariant.outline,
              expand: false,
              onPressed: canGoBack ? () => onPageChanged(filters.page - 1) : null,
            ),
            const SizedBox(width: SpacingTokens.sm),
            AppButton(
              label: 'Next',
              variant: AppButtonVariant.outline,
              expand: false,
              onPressed: canGoForward ? () => onPageChanged(filters.page + 1) : null,
            ),
          ],
        ),
      ],
    );
  }
}
