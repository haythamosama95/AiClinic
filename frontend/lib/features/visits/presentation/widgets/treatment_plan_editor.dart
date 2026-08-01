import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_treatment_plan_editor.dart';

/// Treatment plan prescriptions editor (web `TreatmentPlanEditor`).
class TreatmentPlanEditor extends ConsumerWidget {
  const TreatmentPlanEditor({required this.visitId, super.key});

  final String visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(visitDocumentationProvider(visitId));
    final state = doc.value;
    if (state == null) {
      return const SizedBox.shrink();
    }

    final canEdit = state.canEditWorkspace(ref.read(permissionServiceProvider).canEditVisitSoap());
    final notifier = ref.read(visitDocumentationProvider(visitId).notifier);
    final plans = state.effectiveVisit.treatmentPlans;

    return VisitTreatmentPlanEditor(
      entries: plans,
      canEdit: canEdit,
      onCreate: ({required medicationName, medicationId, dosage, frequency, duration, notes}) =>
          notifier.stageCreateTreatmentPlan(
            medicationName: medicationName,
            medicationId: medicationId,
            dosage: dosage,
            frequency: frequency,
            duration: duration,
            notes: notes,
          ),
      onUpdate: (id, {medicationName, medicationId, dosage, frequency, duration, notes}) =>
          notifier.stageUpdateTreatmentPlan(
            treatmentPlanId: id,
            medicationName: medicationName,
            medicationId: medicationId,
            dosage: dosage,
            frequency: frequency,
            duration: duration,
            notes: notes,
          ),
      onArchive: notifier.stageArchiveTreatmentPlan,
    );
  }
}
