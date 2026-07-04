import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_attachments_panel.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_investigation_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_treatment_plan_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_clinical_note_editor.dart';

/// Treatment phase — plan, medications, investigations, attachments (014 US2).
class EncounterPhasePlan extends StatelessWidget {
  const EncounterPhasePlan({
    required this.visitId,
    required this.state,
    required this.canEdit,
    required this.canUploadAttachments,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final bool canUploadAttachments;

  @override
  Widget build(BuildContext context) {
    final visit = state.visit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VisitClinicalNoteEditor(
          visitId: visitId,
          state: state,
          canEdit: canEdit,
          showStaleBanner: true,
          sections: const {ClinicalNoteSection.plan},
        ),
        const SizedBox(height: AppSpacing.s6),
        EncounterTreatmentPlanList(
          visitId: visitId,
          treatmentPlans: visit.treatmentPlans,
          canEdit: canEdit,
        ),
        const SizedBox(height: AppSpacing.s6),
        EncounterInvestigationList(
          visitId: visitId,
          investigations: visit.investigations,
          canEdit: canEdit,
        ),
        const SizedBox(height: AppSpacing.s6),
        EncounterAttachmentsPanel(
          visitId: visitId,
          branchId: visit.branchId,
          attachments: visit.attachments,
          canUpload: canUploadAttachments && canEdit,
        ),
      ],
    );
  }
}
