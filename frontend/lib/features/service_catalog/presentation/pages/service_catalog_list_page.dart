import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:ai_clinic/features/service_catalog/presentation/models/service_list_filters.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_catalog_list_notifier.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/service_catalog_table.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/service_list_filters_drawer.dart';

/// Service catalog management list (`/settings/services`, 015 US6).
class ServiceCatalogListPage extends ConsumerStatefulWidget {
  const ServiceCatalogListPage({super.key});

  @override
  ConsumerState<ServiceCatalogListPage> createState() => _ServiceCatalogListPageState();
}

class _ServiceCatalogListPageState extends ConsumerState<ServiceCatalogListPage> {
  final _searchController = TextEditingController();
  ServiceListFilters _filters = const ServiceListFilters();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters(ServiceListFilters filters) {
    setState(() => _filters = filters);
    ref.read(serviceCatalogListProvider.notifier).applyFilters(filters);
  }

  void _onSearchChanged(String value) {
    _applyFilters(_filters.copyWith(query: value, page: 1));
  }

  void _onRowTap(ServiceListItem item) {
    if (!AuthRouteGuard.canAccessServiceEditor(ref.read(authSessionProvider))) {
      return;
    }
    context.go(AppRoutes.settingsServiceEdit(item.serviceId));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    final listAsync = ref.watch(serviceCatalogListProvider);
    final canAccess = AuthRouteGuard.canAccessServiceCatalogList(auth);
    final canManage = AuthRouteGuard.canAccessServiceEditor(auth);

    if (!canAccess) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Service catalog',
        description: 'You do not have permission to view services.',
      );
    }

    return listAsync.when(
      skipLoadingOnReload: true,
      loading: () => _buildShell(
        context,
        canManage: canManage,
        body: _buildTable(context, loading: true),
      ),
      error: (error, _) => _buildShell(
        context,
        canManage: canManage,
        body: _buildTable(
          context,
          error: error,
          onRetry: () => ref.read(serviceCatalogListProvider.notifier).reload(),
        ),
      ),
      data: (state) => _buildShell(
        context,
        canManage: canManage,
        state: state,
        body: _buildTable(
          context,
          items: state.items,
          total: state.total,
          filteredEmpty: state.isEmpty && state.filters.hasActiveFilters,
          emptyFirstRun: state.isEmpty && !state.filters.hasActiveFilters,
          onRowTap: canManage ? _onRowTap : null,
          onRetry: () => ref.read(serviceCatalogListProvider.notifier).reload(),
        ),
      ),
    );
  }

  Widget _buildShell(
    BuildContext context, {
    required bool canManage,
    required Widget body,
    ServiceCatalogListUiState? state,
  }) {
    final filters = state?.filters ?? _filters;
    final totalCount = state?.total ?? 0;
    final rowCount = state?.items.length ?? 0;
    final totalPages = totalCount == 0 ? 1 : (totalCount / filters.pageSize).ceil().clamp(1, 1 << 30);
    final currentPage = filters.page.clamp(1, totalPages);

    return ListIndexPattern(
      title: 'Service catalog',
      description: 'Govern organization-wide services, branch pricing, and promotions.',
      toolbarStart: SizedBox(
        width: 280,
        child: AppSearchField(
          controller: _searchController,
          hintText: 'Search services…',
          loading: state == null,
          resultCount: state != null && !state.isEmpty ? totalCount : null,
          onValueChange: _onSearchChanged,
        ),
      ),
      toolbarEnd: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIconButton(
            icon: LucideIcons.slidersHorizontal,
            semanticLabel: 'Filter services',
            onPressed: () => showServiceListFiltersDrawer(
              context,
              filters: filters,
              onFiltersChanged: _applyFilters,
            ),
          ),
        ],
      ),
      toolbarCompactEnd: canManage
          ? AppButton(
              label: 'New service',
              size: AppButtonSize.sm,
              leadingIcon: LucideIcons.plus,
              onPressed: () => context.go(AppRoutes.settingsServicesNew),
            )
          : null,
      headerActions: canManage
          ? AppButton(
              label: 'New service',
              leadingIcon: LucideIcons.plus,
              onPressed: () => context.go(AppRoutes.settingsServicesNew),
            )
          : null,
      filterChips: ServiceListActiveFilterChips(
        filters: filters,
        onFiltersChanged: _applyFilters,
      ),
      table: body,
      page: currentPage,
      pageCount: totalPages,
      onPageChanged: (page) => _applyFilters(filters.copyWith(page: page)),
      paginationLabel: serviceCatalogListRangeSummary(
        filters: filters,
        rowCount: rowCount,
        totalCount: totalCount,
      ),
    );
  }

  Widget _buildTable(
    BuildContext context, {
    List<ServiceListItem> items = const [],
    int total = 0,
    bool loading = false,
    Object? error,
    bool filteredEmpty = false,
    bool emptyFirstRun = false,
    ValueChanged<ServiceListItem>? onRowTap,
    VoidCallback? onRetry,
  }) {
    final canManage = AuthRouteGuard.canAccessServiceEditor(ref.read(authSessionProvider));
    final showBranchPrice = _filters.branchId != null && _filters.branchId!.isNotEmpty;
    final columns = buildServiceCatalogTableColumns(context)
        .where((column) => showBranchPrice || column.id != 'branch_price')
        .toList(growable: false);

    return AppTable<ServiceListItem>(
      columns: columns,
      rowId: (item) => item.serviceId,
      data: items,
      stickyFirstColumn: true,
      loading: loading,
      error: error,
      onRetry: onRetry,
      filteredEmpty: filteredEmpty,
      onRowTap: onRowTap,
      emptyState: AppEmptyState(
        variant: AppEmptyStateVariant.firstRun,
        title: 'No services yet',
        description: 'Create your first catalog service to standardize billing.',
        actionLabel: canManage ? 'New service' : null,
        onAction: canManage ? () => context.go(AppRoutes.settingsServicesNew) : null,
      ),
      filteredEmptyState: const AppEmptyState(
        variant: AppEmptyStateVariant.noResults,
        title: 'No services match your filters',
        description: 'Try adjusting your search or filter criteria.',
      ),
      semanticLabel: 'Service catalog',
      footer: Text(
        serviceCatalogListRangeSummary(
          filters: _filters,
          rowCount: items.length,
          totalCount: total,
        ),
      ),
    );
  }
}
