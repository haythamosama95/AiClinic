import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/create_patient_modal.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patients_empty_state.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patients_toolbar.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patients_table.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patients_table_skeleton.dart';

/// High-density patients list for clinic staff workflows.
class PatientsPage extends ConsumerStatefulWidget {
  const PatientsPage({super.key});

  @override
  ConsumerState<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends ConsumerState<PatientsPage> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  PatientListFilters _filters = const PatientListFilters();

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) {
        return;
      }
      final next = _filters.copyWith(searchText: value, page: 1);
      setState(() => _filters = next);
      ref.read(patientListProvider.notifier).applyFilters(next);
    });
  }

  void _onFiltersChanged(PatientListFilters filters) {
    setState(() => _filters = filters);
    ref.read(patientListProvider.notifier).applyFilters(filters);
  }

  void _onRowTap(PatientTableRow row, Rect? sourceRect) {
    AppNavigator(context).pushPatientDetail(row.item.id, preview: row.item, sourceRect: sourceRect);
  }

  Future<void> _openCreatePatient() async {
    final patientId = await CreatePatientModal.show(context);
    if (patientId == null || !mounted) {
      return;
    }
    ref.invalidate(patientListProvider);
    AppNavigator(context).pushPatientDetail(patientId);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    final listAsync = ref.watch(patientListProvider);
    final canAccess = AuthRouteGuard.canAccessPatientList(auth);
    final canCreate = AuthRouteGuard.canAccessPatientRegistration(auth);

    if (!canAccess) {
      return const _PatientsPermissionDenied();
    }

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: listAsync.when(
        skipLoadingOnReload: true,
        loading: () => _PatientsListShell(
          filters: _filters,
          canCreate: canCreate,
          searchController: _searchController,
          onSearchChanged: _onSearchChanged,
          onFiltersChanged: _onFiltersChanged,
          onAddPatient: canCreate ? () => _openCreatePatient() : null,
          body: const PatientsTableSkeleton(),
        ),
        error: (error, _) => PatientsEmptyState(title: 'Unable to load patients', subtitle: error.toString()),
        data: (state) => _PatientsListShell(
          filters: _filters,
          canCreate: canCreate,
          searchController: _searchController,
          onSearchChanged: _onSearchChanged,
          onFiltersChanged: _onFiltersChanged,
          onAddPatient: canCreate ? () => _openCreatePatient() : null,
          body: _PatientsListBody(
            state: state,
            canCreate: canCreate,
            onRowTap: _onRowTap,
            onAddPatient: canCreate ? () => _openCreatePatient() : null,
            onPageChanged: (page) => _onFiltersChanged(_filters.copyWith(page: page)),
          ),
        ),
      ),
    );
  }
}

class _PatientsListShell extends StatelessWidget {
  const _PatientsListShell({
    required this.filters,
    required this.canCreate,
    required this.searchController,
    required this.onSearchChanged,
    required this.onFiltersChanged,
    required this.body,
    this.onAddPatient,
  });

  final PatientListFilters filters;
  final bool canCreate;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<PatientListFilters> onFiltersChanged;
  final VoidCallback? onAddPatient;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PatientsToolbar(
          searchController: searchController,
          filters: filters,
          canCreate: canCreate,
          onSearchChanged: onSearchChanged,
          onFiltersChanged: onFiltersChanged,
          onAddPatient: onAddPatient,
        ),
        const SizedBox(height: SpacingTokens.md),
        Expanded(child: body),
      ],
    );
  }
}

class _PatientsListBody extends StatelessWidget {
  const _PatientsListBody({
    required this.state,
    required this.canCreate,
    required this.onRowTap,
    required this.onAddPatient,
    required this.onPageChanged,
  });

  final PatientListUiState state;
  final bool canCreate;
  final void Function(PatientTableRow row, Rect? sourceRect) onRowTap;
  final VoidCallback? onAddPatient;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    if (state.searchHint != null) {
      return PatientsEmptyState(
        title: state.searchHint!,
        subtitle: 'Keep typing to search, or clear the field to browse.',
      );
    }

    if (state.isNoPatientsYet) {
      return PatientsEmptyState.noPatientsYet(onAction: onAddPatient);
    }

    if (state.isNoMatch) {
      return const PatientsEmptyState();
    }

    return PatientsTable(
      rows: state.rows,
      totalCount: state.totalCount,
      filters: state.filters,
      onRowTap: onRowTap,
      onPageChanged: onPageChanged,
    );
  }
}

class _PatientsPermissionDenied extends StatelessWidget {
  const _PatientsPermissionDenied();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(SpacingTokens.lg),
        child: Text('You do not have permission to view patients.'),
      ),
    );
  }
}
