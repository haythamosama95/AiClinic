import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/components/app_pagination.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/patients/presentation/add_patient/add_patient_dialog.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_list_controls.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_table.dart';

/// Patients list route (`/patients`).
class PatientsPage extends ConsumerStatefulWidget {
  const PatientsPage({super.key});

  @override
  ConsumerState<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends ConsumerState<PatientsPage> with SingleTickerProviderStateMixin {
  static const _defaultFilters = PatientListFilters(pageSize: 10);

  late final AnimationController _enterController;
  CurvedAnimation? _enterAnimation;
  var _enterStarted = false;
  var _defaultFiltersApplied = false;
  var _addOpen = false;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_enterStarted) {
      _enterStarted = true;
      final reducedMotion = AppMotion.prefersReducedMotion(context);
      _enterController.duration = reducedMotion ? Duration.zero : const Duration(milliseconds: 220);
      _enterAnimation = CurvedAnimation(
        parent: _enterController,
        curve: AppMotion.resolveCurve(AppMotionPreset.rowEnter, reducedMotion: reducedMotion),
      );
      if (reducedMotion) {
        _enterController.value = 1;
      } else {
        _enterController.forward();
      }
    }
  }

  @override
  void dispose() {
    _enterAnimation?.dispose();
    _enterController.dispose();
    super.dispose();
  }

  void _openAddPatient() {
    setState(() => _addOpen = true);
  }

  void _applyFilters(PatientListFilters filters) {
    ref.read(patientListProvider.notifier).applyFilters(filters);
  }

  void _resetPage(PatientListFilters filters) {
    _applyFilters(filters.copyWith(page: 1));
  }

  void _clearAll(PatientListFilters current) {
    _applyFilters(_defaultFilters.copyWith(pageSize: current.pageSize));
  }

  void _clearLastVisitFilter(PatientListFilters current) {
    _resetPage(current.copyWith(lastVisitFilter: PatientLastVisitFilter.any));
  }

  void _ensureDefaultFilters() {
    if (_defaultFiltersApplied) {
      return;
    }
    _defaultFiltersApplied = true;

    final notifier = ref.read(patientListProvider.notifier);
    final filters = notifier.filters;
    if (_isPristineNotifierDefault(filters)) {
      _applyFilters(_defaultFilters);
    }
  }

  bool _isPristineNotifierDefault(PatientListFilters filters) {
    return filters.pageSize == 20 &&
        filters.page == 1 &&
        filters.searchText.isEmpty &&
        filters.branchId == null &&
        filters.lastVisitFilter == PatientLastVisitFilter.any &&
        filters.sortField == PatientSortField.nameAsc;
  }

  bool _hasActiveFilterChips(PatientListFilters filters) {
    return filters.searchText.trim().isNotEmpty || filters.lastVisitFilter != PatientLastVisitFilter.any;
  }

  List<({String id, String label, VoidCallback onRemove})> _activeFilterChips(PatientListFilters filters) {
    final chips = <({String id, String label, VoidCallback onRemove})>[];

    if (filters.searchText.trim().isNotEmpty) {
      chips.add((
        id: 'search',
        label: 'Search: ${filters.searchText.trim()}',
        onRemove: () => _resetPage(filters.copyWith(searchText: '')),
      ));
    }

    if (filters.lastVisitFilter != PatientLastVisitFilter.any) {
      chips.add((
        id: 'lastVisit',
        label: 'Last visit: ${_lastVisitFilterLabel(filters.lastVisitFilter)}',
        onRemove: () => _resetPage(filters.copyWith(lastVisitFilter: PatientLastVisitFilter.any)),
      ));
    }

    return chips;
  }

  String _lastVisitFilterLabel(PatientLastVisitFilter filter) {
    return switch (filter) {
      PatientLastVisitFilter.any => 'Any',
      PatientLastVisitFilter.last30Days => 'Last 30 days',
      PatientLastVisitFilter.last90Days => 'Last 90 days',
      PatientLastVisitFilter.over90Days => 'Over 90 days',
      PatientLastVisitFilter.never => 'Never',
    };
  }

  Widget _buildNoMatchCard(BuildContext context, PatientListFilters filters) {
    final colors = context.appColors;
    final elevation = Theme.of(context).extension<AppElevation>();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        border: Border.all(color: colors.borderSubtle),
        boxShadow: elevation?.shadows1 ?? AppElevation.level1,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6, vertical: 56),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 32, color: colors.iconMuted),
              const SizedBox(height: AppSpacing.space4),
              Text(
                'No patients match',
                style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.space1),
              Text(
                'Try a different search term or clear your filters.',
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.space6),
              AppButton(
                variant: AppButtonVariant.secondary,
                onPressed: () => _clearAll(filters),
                child: const Text('Clear filters'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchHintCard(BuildContext context, String hint) {
    final colors = context.appColors;
    final elevation = Theme.of(context).extension<AppElevation>();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        border: Border.all(color: colors.borderSubtle),
        boxShadow: elevation?.shadows1 ?? AppElevation.level1,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6, vertical: AppSpacing.space8),
        child: Center(
          child: Text(
            hint,
            style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required PatientListUiState? state,
    required PatientListFilters filters,
    required bool isLoading,
  }) {
    if (isLoading && state == null) {
      return PatientTable(rows: const [], loading: true, loadingRows: filters.pageSize);
    }

    if (state == null) {
      return PatientTable(rows: const [], loading: true, loadingRows: filters.pageSize);
    }

    final searchHint = state.searchHint;
    if (searchHint != null) {
      return _buildSearchHintCard(context, searchHint);
    }

    if (state.isNoPatientsYet) {
      return AppEmptyState(
        variant: AppEmptyStateVariant.firstRun,
        title: 'No patients yet',
        description: 'Add your first patient to start building records.',
        action: EmptyStateAction(label: 'Add patient', onPressed: _openAddPatient),
      );
    }

    if (state.isNoMatch) {
      return _buildNoMatchCard(context, filters);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.space6,
      children: [
        PatientTable(
          rows: state.rows,
          loading: isLoading && state.rows.isEmpty,
          loadingRows: filters.pageSize,
          onRowClick: (row) => context.nav.pushPatientDetail(row.item.id, preview: row.item),
        ),
        if (state.rows.isNotEmpty)
          AppPagination(
            page: filters.page,
            pageSize: filters.pageSize,
            total: state.totalCount,
            pageSizeOptions: const [10, 25, 50],
            onPageChange: (page) => _applyFilters(filters.copyWith(page: page)),
            onPageSizeChange: (pageSize) => _applyFilters(filters.copyWith(page: 1, pageSize: pageSize)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureDefaultFilters();

    final listAsync = ref.watch(patientListProvider);
    final state = listAsync.value;
    final filters = state?.filters ?? ref.read(patientListProvider.notifier).filters;
    final isLoading = listAsync.isLoading;
    final hasPatients = state != null && !state.isNoPatientsYet;
    final activeChips = hasPatients
        ? _activeFilterChips(filters)
        : const <({String id, String label, VoidCallback onRemove})>[];

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.space6,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppPageHeader(
                title: 'Patients',
                description: 'Manage patient records, profiles, and medical history.',
              ),
            ),
            AppButton(
              variant: AppButtonVariant.primary,
              size: AppButtonSize.md,
              leadingIcon: const Icon(Icons.person_add),
              onPressed: _openAddPatient,
              child: const Text('Add patient'),
            ),
          ],
        ),
        if (hasPatients)
          PatientListControls(
            filters: filters,
            onSearchChange: (search) => _resetPage(filters.copyWith(searchText: search)),
            onSortChange: (sort) => _resetPage(filters.copyWith(sortField: sort)),
            onLastVisitChange: (lastVisit) => _resetPage(filters.copyWith(lastVisitFilter: lastVisit)),
            onClearFilters: filters.lastVisitFilter != PatientLastVisitFilter.any
                ? () => _clearLastVisitFilter(filters)
                : null,
            activeFilters: activeChips,
            onClearAll: _hasActiveFilterChips(filters) ? () => _clearAll(filters) : null,
          ),
        _buildBody(context: context, state: state, filters: filters, isLoading: isLoading),
      ],
    );

    return Stack(
      children: [
        AppMotion.animatedPreset(
          context: context,
          preset: AppMotionPreset.rowEnter,
          animation: _enterAnimation ?? _enterController,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.hasBoundedHeight) {
                return SingleChildScrollView(child: content);
              }
              return content;
            },
          ),
        ),
        AddPatientDialog(
          open: _addOpen,
          onOpenChange: (open) => setState(() => _addOpen = open),
          onSuccess: (id) => context.nav.pushPatientDetail(id),
        ),
      ],
    );
  }
}
