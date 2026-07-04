import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';

/// Opens the patients filter drawer from the list toolbar.
Future<void> showPatientListFiltersDrawer(
  BuildContext context, {
  required PatientListFilters filters,
  required ValueChanged<PatientListFilters> onFiltersChanged,
}) {
  return showAppDrawer<void>(
    context,
    side: AppDrawerSide.inlineEnd,
    size: AppDrawerSize.md,
    semanticLabel: 'Patient filters',
    builder: (drawerContext, close) {
      return PatientListFiltersDrawer(
        filters: filters,
        onFiltersChanged: onFiltersChanged,
        onClose: close,
      );
    },
  );
}

/// Right-side filter panel for the patients list.
class PatientListFiltersDrawer extends ConsumerStatefulWidget {
  const PatientListFiltersDrawer({
    required this.filters,
    required this.onFiltersChanged,
    required this.onClose,
    super.key,
  });

  final PatientListFilters filters;
  final ValueChanged<PatientListFilters> onFiltersChanged;
  final VoidCallback onClose;

  @override
  ConsumerState<PatientListFiltersDrawer> createState() => _PatientListFiltersDrawerState();
}

class _PatientListFiltersDrawerState extends ConsumerState<PatientListFiltersDrawer> {
  static const _lastVisitOptions = <PatientLastVisitFilter, String>{
    PatientLastVisitFilter.any: 'Any visit',
    PatientLastVisitFilter.last30Days: 'Last 30 days',
    PatientLastVisitFilter.last90Days: 'Last 90 days',
    PatientLastVisitFilter.over90Days: 'Over 90 days ago',
    PatientLastVisitFilter.never: 'Never visited',
  };

  late String? _branchId;
  late PatientLastVisitFilter _lastVisitFilter;

  @override
  void initState() {
    super.initState();
    _branchId = widget.filters.branchId;
    _lastVisitFilter = widget.filters.lastVisitFilter;
  }

  List<AppSelectOption<String>> _branchOptions(List<BranchListItem> branches) {
    return [
      const AppSelectOption(value: '', label: 'Current branch'),
      const AppSelectOption(
        value: PatientListFilters.allBranchesSentinel,
        label: 'All branches',
      ),
      for (final branch in branches)
        AppSelectOption(value: branch.id, label: _branchLabel(branch)),
    ];
  }

  String _branchLabel(BranchListItem branch) {
    final code = branch.code?.trim();
    if (code == null || code.isEmpty) {
      return branch.name;
    }
    return '${branch.name} ($code)';
  }

  String? _branchValueForSelect() {
    final id = _branchId;
    if (id == null || id.isEmpty) {
      return '';
    }
    return id;
  }

  void _clearAll() {
    widget.onFiltersChanged(
      widget.filters.copyWith(
        branchId: null,
        lastVisitFilter: PatientLastVisitFilter.any,
        page: 1,
      ),
    );
    widget.onClose();
  }

  void _applyFilters() {
    widget.onFiltersChanged(
      widget.filters.copyWith(
        branchId: _branchId == null || _branchId!.isEmpty ? null : _branchId,
        lastVisitFilter: _lastVisitFilter,
        page: 1,
      ),
    );
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final branchesAsync = ref.watch(clinicSetupBranchesProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.s6,
              AppSpacing.s6,
              AppSpacing.s4,
              AppSpacing.s4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Filters',
                    style: typography.h3.copyWith(color: colors.textPrimary),
                  ),
                ),
                AppIconButton(
                  icon: LucideIcons.x,
                  semanticLabel: 'Close filters',
                  size: AppIconButtonSize.sm,
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.s6),
              child: branchesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.s12),
                  child: Center(child: AppSpinner()),
                ),
                error: (error, _) => AppAlert(
                  variant: AppAlertVariant.danger,
                  title: 'Unable to load branches',
                  body: error.toString(),
                ),
                data: (branches) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppFormField(
                      label: 'Branch scope',
                      child: AppSelect<String>(
                        options: _branchOptions(branches),
                        value: _branchValueForSelect(),
                        onChanged: (value) => setState(() {
                          _branchId = value.isEmpty ? null : value;
                        }),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    AppFormField(
                      label: 'Last visit',
                      child: AppSelect<PatientLastVisitFilter>(
                        options: [
                          for (final entry in _lastVisitOptions.entries)
                            AppSelectOption(value: entry.key, label: entry.value),
                        ],
                        value: _lastVisitFilter,
                        onChanged: (value) => setState(() => _lastVisitFilter = value),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.all(AppSpacing.s6),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Clear all',
                    variant: AppButtonVariant.secondary,
                    fullWidth: true,
                    onPressed: _clearAll,
                  ),
                ),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: AppButton(
                    label: 'Apply filters',
                    fullWidth: true,
                    onPressed: _applyFilters,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Removable chips summarizing active list filters.
class PatientListActiveFilterChips extends StatelessWidget {
  const PatientListActiveFilterChips({
    required this.filters,
    required this.onFiltersChanged,
    super.key,
  });

  final PatientListFilters filters;
  final ValueChanged<PatientListFilters> onFiltersChanged;

  @override
  Widget build(BuildContext context) {
    if (!filters.hasActiveFilters) {
      return const SizedBox.shrink();
    }

    final chips = <Widget>[];

    if (filters.branchId != null && filters.branchId!.isNotEmpty) {
      final label = filters.isAllBranchesFilter ? 'All branches' : 'Branch filter';
      chips.add(
        AppChip(
          removable: true,
          onRemove: () => onFiltersChanged(
            filters.copyWith(branchId: null, page: 1),
          ),
          child: Text(label),
        ),
      );
    }

    if (filters.lastVisitFilter != PatientLastVisitFilter.any) {
      final label = switch (filters.lastVisitFilter) {
        PatientLastVisitFilter.last30Days => 'Last 30 days',
        PatientLastVisitFilter.last90Days => 'Last 90 days',
        PatientLastVisitFilter.over90Days => 'Over 90 days',
        PatientLastVisitFilter.never => 'Never visited',
        PatientLastVisitFilter.any => 'Any visit',
      };
      chips.add(
        AppChip(
          removable: true,
          onRemove: () => onFiltersChanged(
            filters.copyWith(lastVisitFilter: PatientLastVisitFilter.any, page: 1),
          ),
          child: Text(label),
        ),
      );
    }

    return Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s2,
      children: chips,
    );
  }
}

/// Sort field selector for the patients list toolbar.
class PatientListSortSelect extends StatelessWidget {
  const PatientListSortSelect({
    required this.filters,
    required this.onFiltersChanged,
    super.key,
  });

  final PatientListFilters filters;
  final ValueChanged<PatientListFilters> onFiltersChanged;

  static const _sortOptions = <PatientSortField, String>{
    PatientSortField.nameAsc: 'Name · A to Z',
    PatientSortField.nameDesc: 'Name · Z to A',
    PatientSortField.lastVisitDesc: 'Last visit · Newest',
    PatientSortField.lastVisitAsc: 'Last visit · Oldest',
  };

  @override
  Widget build(BuildContext context) {
    return AppSelect<PatientSortField>(
      options: [
        for (final entry in _sortOptions.entries)
          AppSelectOption(value: entry.key, label: entry.value),
      ],
      value: filters.sortField,
      onChanged: (value) => onFiltersChanged(filters.copyWith(sortField: value, page: 1)),
    );
  }
}

/// Western-digit footer summary for the patients table.
String patientListRangeSummary({
  required PatientListFilters filters,
  required int rowCount,
  required int totalCount,
}) {
  if (totalCount == 0) {
    return 'Showing 0 patients';
  }
  final start = filters.offset + 1;
  final end = (filters.offset + rowCount).clamp(0, totalCount);
  return 'Showing $start–$end of $totalCount';
}
