import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/utils/date_format_utils.dart';
import 'package:ai_clinic/core/widgets/app_data_table.dart';
import 'package:ai_clinic/core/widgets/skeleton_list.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_scope_provider.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/dev_seed_patients_button.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_scope_toggle.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_search_field.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Paginated patient list with scope toggle and search (US2).
class PatientListPage extends ConsumerWidget {
  const PatientListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    final permissions = ref.watch(permissionServiceProvider);
    final canView = permissions.canViewPatients();
    final listAsync = ref.watch(patientListProvider);
    final scope = ref.watch(patientListScopeProvider);

    if (!canView) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Patients'),
          leading: IconButton(tooltip: 'Go back', icon: const Icon(Icons.arrow_back), onPressed: () => context.nav.goHome()),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have permission to view patients.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final activeBranchMissing = auth.context?.activeBranchId == null || auth.context!.activeBranchId!.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients'),
        leading: IconButton(tooltip: 'Go back', icon: const Icon(Icons.arrow_back), onPressed: () => context.nav.goHome()),
        actions: const [DevSeedPatientsButton()],
      ),
      floatingActionButton: permissions.canCreatePatients()
          ? FloatingActionButton.extended(
              key: const Key('patient_list_register_fab'),
              onPressed: () => context.nav.goPatientRegister(),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Register patient'),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: PatientScopeToggle(enabled: !(activeBranchMissing && scope == PatientListScope.thisBranch)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PatientSearchField(
              enabled: !(activeBranchMissing && scope == PatientListScope.thisBranch),
              onSearch: (query) => ref.read(patientListProvider.notifier).reload(searchQuery: query),
            ),
          ),
          if (activeBranchMissing && scope == PatientListScope.thisBranch)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select an active branch in the shell to see patients for this branch.'),
            ),
          Expanded(
            child: listAsync.when(
              loading: () => const SkeletonList(),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Failed to load patients.', style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => ref.invalidate(patientListProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (ui) => _PatientListBody(
                ui: ui,
                showBranchColumn: scope == PatientListScope.allBranches,
                canCreate: permissions.canCreatePatients(),
                onLoadMore: () => ref.read(patientListProvider.notifier).loadMore(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientListBody extends StatelessWidget {
  const _PatientListBody({
    required this.ui,
    required this.showBranchColumn,
    required this.canCreate,
    required this.onLoadMore,
  });

  final PatientListUiState ui;
  final bool showBranchColumn;
  final bool canCreate;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (ui.validationHint != null && ui.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(ui.validationHint!, textAlign: TextAlign.center),
        ),
      );
    }

    if (ui.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ui.searchQuery.isEmpty ? 'No patients in this scope yet.' : 'No patients match your search.',
                textAlign: TextAlign.center,
              ),
              if (canCreate) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('patient_list_empty_register'),
                  onPressed: () => context.nav.goPatientRegister(),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Register patient'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final columns = <AppDataColumn>[
      const AppDataColumn(label: 'Name'),
      const AppDataColumn(label: 'Phone'),
      const AppDataColumn(label: 'Date of birth'),
      if (showBranchColumn) const AppDataColumn(label: 'Branch'),
    ];

    final rows = ui.items.map((item) => _rowCells(item, showBranchColumn: showBranchColumn)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: AppDataTable(
            key: const Key('patient_list_table'),
            columns: columns,
            rows: rows,
            emptyMessage: 'No patients to display',
            onRowTap: (index) => context.nav.pushPatientDetail(ui.items[index].id),
          ),
        ),
        if (ui.loadMoreError != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Failed to load more patients.', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: onLoadMore, child: const Text('Retry')),
                ],
              ),
            ),
          )
        else if (ui.hasMore)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ui.isLoadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      key: const Key('patient_list_load_more'),
                      onPressed: onLoadMore,
                      child: Text('Load more (${ui.items.length} of ${ui.totalCount})'),
                    ),
            ),
          ),
      ],
    );
  }

  List<String> _rowCells(PatientListItem item, {required bool showBranchColumn}) {
    return [item.fullName, item.phone ?? '—', formatDate(item.dateOfBirth), if (showBranchColumn) item.registeringBranchName];
  }
}
