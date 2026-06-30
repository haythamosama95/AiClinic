import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/clinical_note_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachment_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_plan_details_form.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Plan phase — plan prose, treatments, investigations, and attachments (014 US2).
class EncounterPhasePlan extends ConsumerWidget {
  const EncounterPhasePlan({
    required this.visitId,
    required this.state,
    required this.canEdit,
    required this.canUploadAttachments,
    required this.onRefresh,
    this.showClinicalNoteSaveBar = true,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final bool canUploadAttachments;
  final VoidCallback onRefresh;
  final bool showClinicalNoteSaveBar;

  static const _sections = {ClinicalNoteSection.plan};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = state.visit;

    return KeyedSubtree(
      key: const Key('encounter_phase_plan'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VisitSectionCard(
            kind: VisitPanelKind.plan,
            title: 'Treatment notes',
            child: ClinicalNoteEditor(
              visitId: visitId,
              state: state,
              canEdit: canEdit,
              sections: _sections,
              showStaleBanner: false,
              showSaveBar: showClinicalNoteSaveBar,
            ),
          ),
          const SizedBox(height: VisitPageTokens.sectionGap),
          VisitPlanDetailsForm(visitId: visitId, state: state, canEdit: canEdit),
          const SizedBox(height: VisitPageTokens.sectionGap),
          TreatmentPlanList(
            visitId: visitId,
            treatmentPlans: visit.treatmentPlans,
            canEdit: canEdit,
            onChanged: onRefresh,
            sectionKind: VisitPanelKind.treatment,
            sectionTitle: 'Treatment plans',
          ),
          const SizedBox(height: VisitPageTokens.sectionGap),
          InvestigationList(
            visitId: visitId,
            investigations: visit.investigations,
            canEdit: canEdit,
            onChanged: onRefresh,
            sectionKind: VisitPanelKind.investigation,
            sectionTitle: 'Investigations',
          ),
          const SizedBox(height: VisitPageTokens.sectionGap),
          VisitAttachmentList(
            visitId: visitId,
            branchId: visit.branchId,
            attachments: visit.attachments,
            canUpload: canUploadAttachments,
            onChanged: onRefresh,
            sectionKind: VisitPanelKind.attachment,
            sectionTitle: 'Attachments',
          ),
        ],
      ),
    );
  }
}

/// Read-only or editable plan phase content for the detail view.
class EncounterPhasePlanReadOnly extends StatelessWidget {
  const EncounterPhasePlanReadOnly({
    required this.visitId,
    required this.visit,
    required this.canEdit,
    required this.canUploadAttachments,
    required this.onRefresh,
    this.docState,
    super.key,
  });

  final String visitId;
  final VisitDetail visit;
  final bool canEdit;
  final bool canUploadAttachments;
  final VoidCallback onRefresh;
  final VisitDocumentationState? docState;

  @override
  Widget build(BuildContext context) {
    final state =
        docState ??
        VisitDocumentationState(
          visit: visit,
          complaint: visit.documentation?.complaint ?? '',
          history: visit.documentation?.history ?? '',
          examination: visit.documentation?.examination ?? '',
          diagnosis: visit.documentation?.diagnosis ?? '',
          plan: visit.documentation?.plan ?? '',
          expectedUpdatedAt: visit.updatedAt ?? visit.visitDate,
        );

    return EncounterPhasePlan(
      visitId: visitId,
      state: state,
      canEdit: canEdit && docState != null,
      canUploadAttachments: canUploadAttachments,
      onRefresh: onRefresh,
    );
  }
}
