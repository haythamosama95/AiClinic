import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/clinical_note_field.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachments_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_investigations_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_treatment_plan_editor.dart';

/// Treatment step — plan notes, investigations, prescriptions, and attachments.
class VisitTreatmentSection extends ConsumerWidget {
  const VisitTreatmentSection({required this.visitId, required this.canEdit, super.key});

  final String visitId;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docAsync = ref.watch(visitDocumentationProvider(visitId));
    final docState = docAsync.value;
    final notifier = ref.read(visitDocumentationProvider(visitId).notifier);
    final effectiveVisit = docState?.effectiveVisit;
    final investigations = effectiveVisit?.investigations ?? const [];
    final treatmentPlans = effectiveVisit?.treatmentPlans ?? const [];
    final attachments = effectiveVisit?.attachments ?? const [];
    final auth = ref.watch(authSessionProvider);
    final staff = auth.context?.staffProfile;
    final canUploadAttachments = canEdit && staff != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Treatment', style: AppTypography.h2(context)),
        const SizedBox(height: AppSpacing.space1),
        Text(
          'Plan investigations, prescribe treatments, and attach supporting documents.',
          style: AppTypography.bodySm(context).copyWith(color: context.appColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space6),
        ClinicalNoteField(
          visitId: visitId,
          section: ClinicalNoteSection.plan,
          fieldId: 'treatment-notes',
          editorId: 'treatment-notes-input',
          label: 'Treatment notes',
          hint: 'Clinical reasoning, patient education, and follow-up instructions.',
          placeholder: 'Rest, hydration, return if symptoms worsen…',
          canEdit: canEdit,
        ),
        const SizedBox(height: AppSpacing.space6),
        AppFormField(
          id: 'treatment-plan',
          label: 'Treatment plan',
          helperText: 'Add each prescription via the dialog with dosage, frequency, and duration.',
          child: VisitTreatmentPlanEditor(
            entries: treatmentPlans,
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
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        AppFormField(
          id: 'investigations',
          label: 'Investigations needed',
          helperText: 'Add each test via the dialog with any relevant clinical notes.',
          child: VisitInvestigationsEditor(
            entries: investigations,
            canEdit: canEdit,
            onCreate: ({required name, note, investigationId}) =>
                notifier.stageCreateInvestigation(name: name, note: note, investigationId: investigationId),
            onUpdate: (id, {required name, note, investigationId}) => notifier.stageUpdateInvestigation(
              investigationLineId: id,
              name: name,
              note: note,
              investigationId: investigationId,
              updateInvestigationId: true,
            ),
            onArchive: notifier.stageArchiveInvestigation,
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        AppFormField(
          id: 'documents',
          label: 'Attachments',
          helperText: 'Upload lab results, referrals, or other visit documents.',
          child: VisitAttachmentsEditor(
            attachments: attachments,
            canEdit: canUploadAttachments,
            uploadedBy: staff?.staffMemberId ?? '',
            uploadedByName: staff?.fullName,
            onStage: ({required pick, required label, required uploadedBy, uploadedByName}) => notifier.stageAttachment(
              pick: pick,
              label: label,
              uploadedBy: uploadedBy,
              uploadedByName: uploadedByName,
            ),
            onDelete: notifier.stageDeleteAttachment,
          ),
        ),
      ],
    );
  }
}
