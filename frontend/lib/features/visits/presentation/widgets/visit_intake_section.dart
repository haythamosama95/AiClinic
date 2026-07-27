import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/clinical_note_field.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_medical_background_editor.dart';

/// Patient intake step — chief complaint, history, and medical background.
class VisitIntakeSection extends ConsumerWidget {
  const VisitIntakeSection({required this.visitId, required this.canEdit, super.key});

  final String visitId;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docAsync = ref.watch(visitDocumentationProvider(visitId));
    final docState = docAsync.value;

    final patientId = docState?.visit.patientId ?? '';
    final safetyAsync = patientId.isEmpty ? null : ref.watch(patientSafetyProvider(patientId));
    final baseSafety = safetyAsync?.value ?? const PatientSafetyContext();
    final effectiveSafety = docState?.effectivePatientSafety(baseSafety) ?? baseSafety;
    final notifier = ref.read(visitDocumentationProvider(visitId).notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Patient intake', style: AppTypography.h2(context)),
        const SizedBox(height: AppSpacing.space1),
        Text(
          'Record the presenting complaint and relevant medical background.',
          style: AppTypography.bodySm(context).copyWith(color: context.appColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space6),
        ClinicalNoteField(
          visitId: visitId,
          section: ClinicalNoteSection.complaint,
          fieldId: 'chief-complaint',
          editorId: 'chief-complaint-input',
          label: 'Chief complaint',
          requiredMark: true,
          hint: "The primary reason for today's visit, in the patient's own words.",
          placeholder: 'e.g. Persistent cough for 5 days with mild fever…',
          canEdit: canEdit,
        ),
        const SizedBox(height: AppSpacing.space6),
        ClinicalNoteField(
          visitId: visitId,
          section: ClinicalNoteSection.history,
          fieldId: 'history-of-present-illness',
          editorId: 'history-of-present-illness-input',
          label: 'History of present illness',
          hint: 'Onset, duration, severity, aggravating and relieving factors.',
          placeholder: 'Describe the timeline and progression of symptoms…',
          canEdit: canEdit,
        ),
        const SizedBox(height: AppSpacing.space6),
        VisitMedicalBackgroundEditor(
          chronicConditions: effectiveSafety.chronicConditions,
          allergies: effectiveSafety.allergies,
          currentMedications: effectiveSafety.currentMedications,
          canEdit: canEdit,
          onCreateCondition: (title, note) => notifier.stageCreateCondition(name: title, note: note),
          onUpdateCondition: (id, title, note) =>
              notifier.stageUpdateCondition(conditionId: id, name: title, note: note),
          onArchiveCondition: notifier.stageArchiveCondition,
          onCreateAllergy: (title, note) => notifier.stageCreateAllergy(substance: title, reaction: note),
          onUpdateAllergy: (id, title, note) =>
              notifier.stageUpdateAllergy(allergyId: id, substance: title, reaction: note),
          onArchiveAllergy: notifier.stageArchiveAllergy,
          onCreateMedication: (title, note) => notifier.stageCreateMedication(name: title, note: note),
          onUpdateMedication: (id, title, note) =>
              notifier.stageUpdateMedication(medicationRecordId: id, name: title, note: note),
          onArchiveMedication: notifier.stageArchiveMedication,
        ),
      ],
    );
  }
}
