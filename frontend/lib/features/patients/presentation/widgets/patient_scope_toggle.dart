import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_scope_provider.dart';

/// Switches patient list between active branch and all branches (US2).
class PatientScopeToggle extends ConsumerWidget {
  const PatientScopeToggle({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(patientListScopeProvider);

    return SegmentedButton<PatientListScope>(
      key: const Key('patient_scope_toggle'),
      segments: const [
        ButtonSegment(value: PatientListScope.thisBranch, label: Text('This branch only')),
        ButtonSegment(value: PatientListScope.allBranches, label: Text('All branches')),
      ],
      selected: {scope},
      onSelectionChanged: enabled
          ? (selection) {
              ref.read(patientListScopeProvider.notifier).setScope(selection.first);
            }
          : null,
    );
  }
}
