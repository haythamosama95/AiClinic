import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/presentation/models/service_list_filters.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';

/// Opens the service catalog filter drawer from the list toolbar.
Future<void> showServiceListFiltersDrawer(
  BuildContext context, {
  required ServiceListFilters filters,
  required ValueChanged<ServiceListFilters> onFiltersChanged,
}) {
  return showAppDrawer<void>(
    context,
    side: AppDrawerSide.inlineEnd,
    size: AppDrawerSize.md,
    semanticLabel: 'Service catalog filters',
    builder: (drawerContext, close) {
      return ServiceListFiltersDrawer(
        filters: filters,
        onFiltersChanged: onFiltersChanged,
        onClose: close,
      );
    },
  );
}

/// Filter panel for the service catalog list (015 US6).
class ServiceListFiltersDrawer extends ConsumerStatefulWidget {
  const ServiceListFiltersDrawer({
    required this.filters,
    required this.onFiltersChanged,
    required this.onClose,
    super.key,
  });

  final ServiceListFilters filters;
  final ValueChanged<ServiceListFilters> onFiltersChanged;
  final VoidCallback onClose;

  @override
  ConsumerState<ServiceListFiltersDrawer> createState() => _ServiceListFiltersDrawerState();
}

class _ServiceListFiltersDrawerState extends ConsumerState<ServiceListFiltersDrawer> {
  late GlobalStatus? _globalStatus;
  late String? _branchId;

  @override
  void initState() {
    super.initState();
    _globalStatus = widget.filters.globalStatus;
    _branchId = widget.filters.branchId;
  }

  List<AppSelectOption<String>> _branchOptions(List<BranchListItem> branches) {
    return [
      const AppSelectOption(value: '', label: 'All branches'),
      for (final branch in branches)
        if (branch.isActive) AppSelectOption(value: branch.id, label: branch.name),
    ];
  }

  String _branchValueForSelect() {
    final branchId = _branchId;
    if (branchId == null || branchId.isEmpty) {
      return '';
    }
    return branchId;
  }

  void _applyFilters() {
    widget.onFiltersChanged(
      widget.filters.copyWith(
        globalStatus: _globalStatus,
        clearGlobalStatus: _globalStatus == null,
        branchId: _branchId == null || _branchId!.isEmpty ? null : _branchId,
        clearBranchId: _branchId == null || _branchId!.isEmpty,
        page: 1,
      ),
    );
    widget.onClose();
  }

  void _clearAll() {
    widget.onFiltersChanged(const ServiceListFilters());
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
                      label: 'Global status',
                      child: AppSelect<GlobalStatus?>(
                        options: const [
                          AppSelectOption(value: null, label: 'Any status'),
                          AppSelectOption(value: GlobalStatus.active, label: 'Active'),
                          AppSelectOption(value: GlobalStatus.inactive, label: 'Inactive'),
                        ],
                        value: _globalStatus,
                        onChanged: (value) => setState(() => _globalStatus = value),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    AppFormField(
                      label: 'Branch',
                      helperText: 'When set, shows branch-specific effective price and status.',
                      child: AppSelect<String>(
                        options: _branchOptions(branches),
                        value: _branchValueForSelect(),
                        onChanged: (value) => setState(() {
                          _branchId = value.isEmpty ? null : value;
                        }),
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

/// Active filter chips for the service catalog list toolbar.
class ServiceListActiveFilterChips extends ConsumerWidget {
  const ServiceListActiveFilterChips({
    required this.filters,
    required this.onFiltersChanged,
    super.key,
  });

  final ServiceListFilters filters;
  final ValueChanged<ServiceListFilters> onFiltersChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!filters.hasActiveFilters) {
      return const SizedBox.shrink();
    }

    final branchesAsync = ref.watch(clinicSetupBranchesProvider);
    final branchNameById = branchesAsync.maybeWhen(
      data: (branches) => {for (final branch in branches) branch.id: branch.name},
      orElse: () => const <String, String>{},
    );

    final chips = <Widget>[];
    final query = filters.query.trim();
    if (query.isNotEmpty) {
      chips.add(
        AppChip(
          removable: true,
          onRemove: () => onFiltersChanged(filters.copyWith(query: '', page: 1)),
          child: Text('Search: $query'),
        ),
      );
    }
    if (filters.globalStatus != null) {
      chips.add(
        AppChip(
          removable: true,
          onRemove: () => onFiltersChanged(filters.copyWith(clearGlobalStatus: true, page: 1)),
          child: Text('Status: ${filters.globalStatus!.name}'),
        ),
      );
    }
    if (filters.branchId != null && filters.branchId!.isNotEmpty) {
      final branchLabel = branchNameById[filters.branchId] ?? filters.branchId!;
      chips.add(
        AppChip(
          removable: true,
          onRemove: () => onFiltersChanged(filters.copyWith(clearBranchId: true, page: 1)),
          child: Text('Branch: $branchLabel'),
        ),
      );
    }

    return Wrap(spacing: AppSpacing.s2, runSpacing: AppSpacing.s2, children: chips);
  }
}

String serviceCatalogListRangeSummary({
  required ServiceListFilters filters,
  required int rowCount,
  required int totalCount,
}) {
  if (totalCount == 0) {
    return 'No services';
  }
  final start = filters.offset + 1;
  final end = filters.offset + rowCount;
  return '$start–$end of $totalCount services';
}
