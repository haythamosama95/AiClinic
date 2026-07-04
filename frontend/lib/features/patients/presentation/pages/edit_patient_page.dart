import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_editor_form.dart';

/// Full-page patient edit flow (`/patients/:patientId/edit`).
class EditPatientPage extends ConsumerWidget {
  const EditPatientPage({required this.patientId, super.key});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(patientDetailProvider(patientId));

    return detailAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: AppSpinner()),
      error: (error, _) => AppErrorState(
        message: error.toString(),
        onRetry: () => ref.invalidate(patientDetailProvider(patientId)),
      ),
      data: (detail) => PatientEditorForm(patient: detail),
    );
  }
}
