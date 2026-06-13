import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';

const _sidebarWidth = 400.0;

/// Opens the patients filter sidebar from the right edge.
class PatientsFilterButton extends ConsumerStatefulWidget {
  const PatientsFilterButton({required this.filters, required this.onFiltersChanged, super.key});

  final PatientListFilters filters;
  final ValueChanged<PatientListFilters> onFiltersChanged;

  @override
  ConsumerState<PatientsFilterButton> createState() => _PatientsFilterButtonState();
}

class _PatientsFilterButtonState extends ConsumerState<PatientsFilterButton> {
  var _isHovered = false;

  Future<void> _openSidebar() async {
    await AppSheets.showModal<void>(
      context: context,
      side: AppSheetSide.right,
      width: _sidebarWidth,
      builder: (context) => PatientsFilterSidebar(filters: widget.filters, onFiltersChanged: widget.onFiltersChanged),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final filterCount = widget.filters.activeFilterCount;

    return Tooltip(
      message: filterCount > 0 ? 'Filters active' : 'Filter patients',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _openSidebar,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Badge(
              isLabelVisible: filterCount > 0,
              label: Text('$filterCount'),
              backgroundColor: colors.primaryForeground,
              textColor: colors.primary,
              child: Material(
                color: _isHovered
                    ? Color.alphaBlend(colors.primaryForeground.withValues(alpha: 0.15), colors.primary)
                    : colors.primary,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: Center(child: Icon(Icons.filter_list_outlined, color: colors.primaryForeground, size: 20)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Right-side filter panel for the patients list.
class PatientsFilterSidebar extends ConsumerStatefulWidget {
  const PatientsFilterSidebar({required this.filters, required this.onFiltersChanged, super.key});

  final PatientListFilters filters;
  final ValueChanged<PatientListFilters> onFiltersChanged;

  @override
  ConsumerState<PatientsFilterSidebar> createState() => _PatientsFilterSidebarState();
}

class _PatientsFilterSidebarState extends ConsumerState<PatientsFilterSidebar> {
  static const _lastVisitOptions = <String, PatientLastVisitFilter>{
    'Any visit': PatientLastVisitFilter.any,
    'Last 30 days': PatientLastVisitFilter.last30Days,
    'Last 90 days': PatientLastVisitFilter.last90Days,
    'Over 90 days ago': PatientLastVisitFilter.over90Days,
    'Never visited': PatientLastVisitFilter.never,
  };

  late String? _branchId;
  late PatientLastVisitFilter _lastVisitFilter;

  @override
  void initState() {
    super.initState();
    _branchId = widget.filters.branchId;
    _lastVisitFilter = widget.filters.lastVisitFilter;
  }

  Map<String, String> _branchItems(List<BranchListItem> branches) {
    return {
      'Current branch': '',
      'All branches': PatientListFilters.allBranchesSentinel,
      for (final branch in branches) _branchLabel(branch): branch.id,
    };
  }

  String _branchLabel(BranchListItem branch) {
    final code = branch.code?.trim();
    if (code == null || code.isEmpty) {
      return branch.name;
    }
    return '${branch.name} ($code)';
  }

  String? _branchValueForFilter() {
    final id = _branchId;
    if (id == null || id.isEmpty) {
      return '';
    }
    return id;
  }

  void _clearAll() {
    widget.onFiltersChanged(
      widget.filters.copyWith(branchId: null, lastVisitFilter: PatientLastVisitFilter.any, page: 1),
    );
    Navigator.of(context).pop();
  }

  void _applyFilters() {
    widget.onFiltersChanged(
      widget.filters.copyWith(
        branchId: _branchId == null || _branchId!.isEmpty ? null : _branchId,
        lastVisitFilter: _lastVisitFilter,
        page: 1,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final branchesAsync = ref.watch(clinicSetupBranchesProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.lg, SpacingTokens.md, SpacingTokens.md),
            child: Row(
              children: [
                Expanded(
                  child: Text('Filters', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                AppIconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg),
              child: branchesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: SpacingTokens.xl),
                  child: Center(child: AppCircularProgress()),
                ),
                error: (error, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Failed to load branches: $error',
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.destructive),
                    ),
                    const SizedBox(height: SpacingTokens.lg),
                    AppFilterSelect<String>(
                      label: 'Branch',
                      hintText: 'Current branch',
                      items: const {'Current branch': ''},
                      value: '',
                      enabled: false,
                      onChanged: (_) {},
                    ),
                  ],
                ),
                data: (branches) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppFilterSelect<String>(
                      label: 'Branch',
                      hintText: _branchItems(branches).entries
                          .firstWhere(
                            (e) => e.value == (_branchValueForFilter() ?? ''),
                            orElse: () => const MapEntry('Current branch', ''),
                          )
                          .key,
                      items: _branchItems(branches),
                      value: _branchValueForFilter(),
                      onChanged: (value) => setState(() => _branchId = value == null || value.isEmpty ? null : value),
                    ),
                    const SizedBox(height: SpacingTokens.lg),
                    AppFilterSelect<PatientLastVisitFilter>(
                      label: 'Last Visit',
                      items: _lastVisitOptions,
                      value: _lastVisitFilter,
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => _lastVisitFilter = value);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          _FilterSidebarFooter(onClearAll: _clearAll, onApplyFilters: _applyFilters),
        ],
      ),
    );
  }
}

class _FilterSidebarFooter extends StatelessWidget {
  const _FilterSidebarFooter({required this.onClearAll, required this.onApplyFilters});

  final VoidCallback onClearAll;
  final VoidCallback onApplyFilters;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: 0.45),
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppButton(label: 'Apply Filters', size: AppFieldSize.sm, onPressed: onApplyFilters),
            const SizedBox(height: SpacingTokens.sm),
            AppButton(
              label: 'Clear All',
              variant: AppButtonVariant.outline,
              size: AppFieldSize.sm,
              onPressed: onClearAll,
            ),
          ],
        ),
      ),
    );
  }
}
