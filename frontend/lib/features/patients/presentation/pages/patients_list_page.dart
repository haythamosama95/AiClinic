import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_query.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_list_filters_drawer.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patients_table_widget.dart';

/// High-density patients list for clinic staff workflows.
class PatientsListPage extends ConsumerStatefulWidget {
  const PatientsListPage({super.key});

  @override
  ConsumerState<PatientsListPage> createState() => _PatientsListPageState();
}

class _PatientsListPageState extends ConsumerState<PatientsListPage> {
  final _searchController = TextEditingController();
  PatientListFilters _filters = const PatientListFilters();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters(PatientListFilters filters) {
    setState(() => _filters = filters);
    ref.read(patientListProvider.notifier).applyFilters(filters);
  }

  void _onSearchChanged(String value) {
    _applyFilters(_filters.copyWith(searchText: value, page: 1));
  }

  void _onSortChanged(String? columnId, AppTableSortDirection? direction) {
    final sortField = patientSortFieldForColumn(columnId, direction);
    if (sortField == null) {
      return;
    }
    _applyFilters(_filters.copyWith(sortField: sortField, page: 1));
  }

  void _onRowTap(PatientTableRow row) {
    context.nav.pushPatientDetail(row.item.id, preview: row.item);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    final listAsync = ref.watch(patientListProvider);
    final canAccess = AuthRouteGuard.canAccessPatientList(auth);
    final canCreate = AuthRouteGuard.canAccessPatientRegistration(auth);

    if (!canAccess) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Patients',
        description: 'You do not have permission to view patients.',
      );
    }

    return listAsync.when(
      skipLoadingOnReload: true,
      loading: () => _buildShell(
        context,
        canCreate: canCreate,
        body: _buildTable(context, loading: true),
      ),
      error: (error, _) => _buildShell(
        context,
        canCreate: canCreate,
        body: _buildTable(
          context,
          error: error,
          onRetry: () => ref.read(patientListProvider.notifier).reload(),
        ),
      ),
      data: (state) {
        if (state.searchHint != null) {
          return _buildShell(
            context,
            canCreate: canCreate,
            searchHint: state.searchHint,
            body: AppEmptyState(
              variant: AppEmptyStateVariant.noResults,
              title: state.searchHint!,
              description: PatientSearchQuery.helperForDraft(_filters.searchText),
            ),
          );
        }

        return _buildShell(
          context,
          canCreate: canCreate,
          state: state,
          body: _buildTable(
            context,
            rows: state.rows,
            totalCount: state.totalCount,
            filteredEmpty: state.isNoMatch,
            emptyFirstRun: state.isNoPatientsYet,
            onRowTap: _onRowTap,
            onRetry: () => ref.read(patientListProvider.notifier).reload(),
          ),
        );
      },
    );
  }

  Widget _buildShell(
    BuildContext context, {
    required bool canCreate,
    required Widget body,
    PatientListUiState? state,
    String? searchHint,
  }) {
    final filters = state?.filters ?? _filters;
    final totalCount = state?.totalCount ?? 0;
    final rowCount = state?.rows.length ?? 0;
    final totalPages = totalCount == 0
        ? 1
        : (totalCount / filters.pageSize).ceil().clamp(1, 1 << 30);
    final currentPage = filters.page.clamp(1, totalPages);

    return ListIndexPattern(
      title: 'Patients',
      description: 'Search and manage patients registered at your clinic.',
      toolbarStart: SizedBox(
        width: 280,
        child: AppSearchField(
          controller: _searchController,
          hintText: 'Search by name or phone…',
          loading: state == null && searchHint == null,
          resultCount: state?.isEmptyResult == false ? totalCount : null,
          onValueChange: _onSearchChanged,
        ),
      ),
      toolbarEnd: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIconButton(
            icon: LucideIcons.slidersHorizontal,
            semanticLabel: 'Filter patients',
            onPressed: () => showPatientListFiltersDrawer(
              context,
              filters: filters,
              onFiltersChanged: _applyFilters,
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          SizedBox(
            width: 200,
            child: PatientListSortSelect(
              filters: filters,
              onFiltersChanged: _applyFilters,
            ),
          ),
        ],
      ),
      toolbarCompactEnd: canCreate
          ? AppButton(
              label: 'Register patient',
              size: AppButtonSize.sm,
              leadingIcon: LucideIcons.plus,
              onPressed: () => context.nav.goPatientRegister(),
            )
          : null,
      headerActions: canCreate
          ? AppButton(
              label: 'Register patient',
              leadingIcon: LucideIcons.plus,
              onPressed: () => context.nav.goPatientRegister(),
            )
          : null,
      filterChips: PatientListActiveFilterChips(
        filters: filters,
        onFiltersChanged: _applyFilters,
      ),
      table: body,
      page: currentPage,
      pageCount: totalPages,
      onPageChanged: (page) => _applyFilters(filters.copyWith(page: page)),
      paginationLabel: patientListRangeSummary(
        filters: filters,
        rowCount: rowCount,
        totalCount: totalCount,
      ),
    );
  }

  Widget _buildTable(
    BuildContext context, {
    List<PatientTableRow> rows = const [],
    int totalCount = 0,
    bool loading = false,
    Object? error,
    bool filteredEmpty = false,
    bool emptyFirstRun = false,
    ValueChanged<PatientTableRow>? onRowTap,
    VoidCallback? onRetry,
  }) {
    final (sortColumnId, sortDirection) = patientTableSortState(_filters.sortField);
    final canCreate = AuthRouteGuard.canAccessPatientRegistration(ref.read(authSessionProvider));

    return AppTable<PatientTableRow>(
      columns: buildPatientTableColumns(context),
      rowId: (row) => row.item.id,
      data: rows,
      stickyFirstColumn: true,
      loading: loading,
      error: error,
      onRetry: onRetry,
      filteredEmpty: filteredEmpty,
      sortColumnId: sortColumnId,
      sortDirection: sortDirection,
      onSortChanged: _onSortChanged,
      onRowTap: onRowTap,
      emptyState: AppEmptyState(
        variant: AppEmptyStateVariant.firstRun,
        title: 'No patients yet',
        description: 'Get started by registering your first patient.',
        actionLabel: canCreate ? 'Register patient' : null,
        onAction: canCreate ? () => context.nav.goPatientRegister() : null,
      ),
      filteredEmptyState: const AppEmptyState(
        variant: AppEmptyStateVariant.noResults,
        title: 'No patients match your search criteria',
        description: 'Try adjusting your filters or search terms.',
      ),
      semanticLabel: 'Patients',
      footer: Text(
        patientListRangeSummary(
          filters: _filters,
          rowCount: rows.length,
          totalCount: totalCount,
        ),
      ),
    );
  }
}
