import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/providers/workspace_mode_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/clinical_note_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_field_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachment_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

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
    final isExpertScroll = ref.watch(workspaceModeProvider) == WorkspaceMode.expert;
    final visit = state.visit;

    return KeyedSubtree(
      key: const Key('encounter_phase_plan'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final expandField = isExpertScroll || (constraints.hasBoundedHeight && constraints.maxHeight.isFinite);
          if (expandField) {
            return SizedBox(
              height: constraints.maxHeight,
              child: _buildPlanGrid(visit: visit, expandField: true, isExpertScroll: isExpertScroll),
            );
          }
          return _buildPlanGrid(visit: visit, expandField: false, isExpertScroll: isExpertScroll);
        },
      ),
    );
  }

  Widget _buildPlanGrid({required VisitDetail visit, required bool expandField, required bool isExpertScroll}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useGrid = constraints.maxWidth >= 900;

        final treatmentNotes = _treatmentNotesCard(expandField: expandField);
        final treatmentPlans = TreatmentPlanList(
          visitId: visitId,
          treatmentPlans: visit.treatmentPlans,
          canEdit: canEdit,
          deferPersistence: canEdit,
          onChanged: onRefresh,
          sectionKind: VisitPanelKind.treatment,
          sectionTitle: 'Treatment plans',
          encounterShell: true,
          expandBody: expandField,
        );
        final investigations = InvestigationList(
          visitId: visitId,
          investigations: visit.investigations,
          canEdit: canEdit,
          deferPersistence: canEdit,
          onChanged: onRefresh,
          sectionKind: VisitPanelKind.investigation,
          sectionTitle: 'Investigations',
          encounterShell: true,
          expandBody: expandField,
        );
        final attachments = VisitAttachmentList(
          visitId: visitId,
          branchId: visit.branchId,
          attachments: visit.attachments,
          canUpload: canUploadAttachments,
          deferPersistence: canEdit,
          onChanged: onRefresh,
          sectionKind: VisitPanelKind.attachment,
          sectionTitle: 'Attachments',
          encounterShell: true,
          expandBody: expandField,
        );

        if (!useGrid) {
          if (!expandField) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                treatmentNotes,
                const SizedBox(height: VisitPageTokens.sectionGap),
                treatmentPlans,
                const SizedBox(height: VisitPageTokens.sectionGap),
                investigations,
                const SizedBox(height: VisitPageTokens.sectionGap),
                attachments,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: treatmentNotes),
              const SizedBox(height: VisitPageTokens.sectionGap),
              Expanded(child: treatmentPlans),
              const SizedBox(height: VisitPageTokens.sectionGap),
              Expanded(child: investigations),
              const SizedBox(height: VisitPageTokens.sectionGap),
              Expanded(child: attachments),
            ],
          );
        }

        final topRow = Row(
          crossAxisAlignment: expandField ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
          children: [
            Expanded(flex: isExpertScroll ? 3 : 1, child: treatmentNotes),
            const SizedBox(width: VisitPageTokens.sectionGap),
            Expanded(flex: isExpertScroll ? 2 : 1, child: treatmentPlans),
          ],
        );

        final bottomRow = Row(
          crossAxisAlignment: expandField ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
          children: [
            Expanded(child: investigations),
            const SizedBox(width: VisitPageTokens.sectionGap),
            Expanded(child: attachments),
          ],
        );

        if (!expandField) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              topRow,
              const SizedBox(height: VisitPageTokens.sectionGap),
              bottomRow,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: topRow),
            const SizedBox(height: VisitPageTokens.sectionGap),
            Expanded(child: bottomRow),
          ],
        );
      },
    );
  }

  Widget _treatmentNotesCard({required bool expandField}) {
    return EncounterFieldCard(
      title: 'Treatment notes',
      titleIcon: VisitPanelKind.plan.icon,
      expandBody: expandField,
      embedTitleInToolbar: true,
      child: ClinicalNoteEditor(
        visitId: visitId,
        state: state,
        canEdit: canEdit,
        sections: _sections,
        showSectionHeaders: false,
        expandField: expandField,
        useRichTextParagraph: true,
        removeBorder: true,
        showStaleBanner: false,
        showSaveBar: showClinicalNoteSaveBar,
        showEditButton: true,
        toolbarLeading: const EncounterToolbarTitle(title: 'Treatment notes', icon: Icons.assignment_outlined),
        emptyStateIcon: Icons.assignment_outlined,
        emptyStateText: 'Start entering the treatment notes',
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
          persistedVisit: visit,
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
