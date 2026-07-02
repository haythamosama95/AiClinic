import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/clinical_note_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_field_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_result_capture_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_signs_tracking_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

export 'package:ai_clinic/features/visits/presentation/widgets/vital_signs_tracking_card.dart' show BmiChip;

/// Findings & Diagnosis phase — examination, diagnosis, and vital signs (014 US2).
class EncounterPhaseObjective extends ConsumerWidget {
  const EncounterPhaseObjective({
    required this.visitId,
    required this.state,
    required this.canEdit,
    required this.onRefresh,
    this.showClinicalNoteSaveBar = true,
    this.expertMode = false,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final VoidCallback onRefresh;
  final bool showClinicalNoteSaveBar;
  final bool expertMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KeyedSubtree(
      key: const Key('encounter_phase_objective'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final expandField = expertMode || (constraints.hasBoundedHeight && constraints.maxHeight.isFinite);
          final mainLayout = expandField
              ? SizedBox(height: constraints.maxHeight, child: _buildFindingsLayout(expandField: true))
              : _buildFindingsLayout(expandField: false);

          final pendingInvestigations = state.visit.pendingInvestigations;
          if (pendingInvestigations.isEmpty) {
            return mainLayout;
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (expandField) Expanded(child: mainLayout) else mainLayout,
              const SizedBox(height: VisitPageTokens.sectionGap),
              InvestigationResultCaptureList(
                pendingInvestigations: pendingInvestigations,
                canEdit: canEdit,
                visitId: visitId,
                deferPersistence: canEdit,
                onChanged: onRefresh,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFindingsLayout({required bool expandField}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSideBySide = constraints.maxWidth >= 900;
        final findingsColumn = _examinationDiagnosisColumn(expandField: expandField);

        final vitalSignsCard = VitalSignsTrackingCard(
          visitId: visitId,
          vitalSigns: state.visit.vitalSigns,
          predefinedVitalSigns: state.predefinedVitalSigns,
          canEdit: canEdit,
          deferPersistence: canEdit,
          onChanged: onRefresh,
          expandBody: expandField,
        );

        if (!useSideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              findingsColumn,
              const SizedBox(height: VisitPageTokens.sectionGap),
              vitalSignsCard,
            ],
          );
        }

        if (!expandField) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: findingsColumn),
              const SizedBox(width: VisitPageTokens.sectionGap),
              Expanded(flex: 2, child: vitalSignsCard),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: findingsColumn),
            const SizedBox(width: VisitPageTokens.sectionGap),
            Expanded(flex: 2, child: vitalSignsCard),
          ],
        );
      },
    );
  }

  Widget _examinationDiagnosisColumn({required bool expandField}) {
    final examination = EncounterFieldCard(
      title: 'Examination',
      titleIcon: Icons.medical_services_outlined,
      expandBody: expandField,
      embedTitleInToolbar: true,
      child: ClinicalNoteEditor(
        visitId: visitId,
        state: state,
        canEdit: canEdit,
        sections: const {ClinicalNoteSection.examination},
        showSectionHeaders: false,
        expandField: expandField,
        useRichTextParagraph: true,
        removeBorder: true,
        showStaleBanner: false,
        showSaveBar: showClinicalNoteSaveBar,
        showEditButton: true,
        toolbarLeading: const EncounterToolbarTitle(title: 'Examination', icon: Icons.medical_services_outlined),
        emptyStateIcon: Icons.medical_services_outlined,
        emptyStateText: 'Start entering the examination',
      ),
    );

    final diagnosis = EncounterFieldCard(
      title: 'Diagnosis',
      titleIcon: Icons.medical_information_outlined,
      expandBody: expandField,
      embedTitleInToolbar: true,
      child: ClinicalNoteEditor(
        visitId: visitId,
        state: state,
        canEdit: canEdit,
        sections: const {ClinicalNoteSection.diagnosis},
        showSectionHeaders: false,
        expandField: expandField,
        useRichTextParagraph: true,
        removeBorder: true,
        showStaleBanner: false,
        showSaveBar: false,
        toolbarLeading: const EncounterToolbarTitle(title: 'Diagnosis', icon: Icons.medical_information_outlined),
        emptyStateIcon: Icons.medical_information_outlined,
        emptyStateText: 'Start entering the diagnosis',
      ),
    );

    if (!expandField) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          examination,
          const SizedBox(height: VisitPageTokens.sectionGap),
          diagnosis,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: examination),
        const SizedBox(height: VisitPageTokens.sectionGap),
        Expanded(child: diagnosis),
      ],
    );
  }
}

/// Objective content for the detail view.
class EncounterPhaseObjectiveDetail extends StatelessWidget {
  const EncounterPhaseObjectiveDetail({
    required this.visitId,
    required this.visit,
    required this.canEdit,
    required this.onRefresh,
    this.docState,
    super.key,
  });

  final String visitId;
  final VisitDetail visit;
  final bool canEdit;
  final VoidCallback onRefresh;
  final VisitDocumentationState? docState;

  @override
  Widget build(BuildContext context) {
    if (canEdit && docState != null) {
      return EncounterPhaseObjective(visitId: visitId, state: docState!, canEdit: true, onRefresh: onRefresh);
    }

    final readOnlyColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EncounterFieldCard(
          title: 'Examination',
          titleIcon: Icons.medical_services_outlined,
          child: EncounterDetailText(value: visit.documentation?.examination ?? ''),
        ),
        const SizedBox(height: VisitPageTokens.sectionGap),
        EncounterFieldCard(
          title: 'Diagnosis',
          titleIcon: Icons.medical_information_outlined,
          child: EncounterDetailText(value: visit.documentation?.diagnosis ?? ''),
        ),
      ],
    );

    final pendingInvestigations = visit.pendingInvestigations;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSideBySide = constraints.maxWidth >= 900;
        final vitalSignsCard = VitalSignsTrackingCardReadOnly(vitalSigns: visit.vitalSigns);

        Widget mainLayout;
        if (!useSideBySide) {
          mainLayout = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              readOnlyColumn,
              const SizedBox(height: VisitPageTokens.sectionGap),
              vitalSignsCard,
            ],
          );
        } else {
          mainLayout = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: readOnlyColumn),
              const SizedBox(width: VisitPageTokens.sectionGap),
              Expanded(flex: 2, child: vitalSignsCard),
            ],
          );
        }

        if (pendingInvestigations.isEmpty) {
          return mainLayout;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            mainLayout,
            const SizedBox(height: VisitPageTokens.sectionGap),
            InvestigationResultCaptureList(
              pendingInvestigations: pendingInvestigations,
              canEdit: false,
              onChanged: onRefresh,
            ),
          ],
        );
      },
    );
  }
}

class EncounterPhaseExaminationFromVisit extends StatelessWidget {
  const EncounterPhaseExaminationFromVisit({required this.note, super.key});

  final VisitClinicalNote? note;

  @override
  Widget build(BuildContext context) {
    return VisitDetailField(label: 'Examination', value: note?.examination ?? '', abbr: 'E');
  }
}

class EncounterPhaseDiagnosisFromVisit extends StatelessWidget {
  const EncounterPhaseDiagnosisFromVisit({required this.note, super.key});

  final VisitClinicalNote? note;

  @override
  Widget build(BuildContext context) {
    return VisitDetailField(label: 'Diagnosis', value: note?.diagnosis ?? '', abbr: 'D');
  }
}
