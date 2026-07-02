import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/clinical_note_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_field_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/patient_health_tracking_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Subjective phase — Complaint, History, and patient context (014 US2).
class EncounterPhaseSubjective extends ConsumerWidget {
  const EncounterPhaseSubjective({
    required this.visitId,
    required this.state,
    required this.canEdit,
    this.showClinicalNoteSaveBar = true,
    this.expertMode = false,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final bool showClinicalNoteSaveBar;
  final bool expertMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KeyedSubtree(
      key: const Key('encounter_phase_subjective'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final expandField = expertMode || (constraints.hasBoundedHeight && constraints.maxHeight.isFinite);
          if (expandField) {
            return SizedBox(height: constraints.maxHeight, child: _buildIntakeLayout(expandField: true));
          }
          return _buildIntakeLayout(expandField: false);
        },
      ),
    );
  }

  Widget _buildIntakeLayout({required bool expandField}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSideBySide = constraints.maxWidth >= 900;
        final intakeColumn = _complaintHistoryColumn(expandField: expandField);

        final healthCard = PatientHealthTrackingCard(
          patientId: state.visit.patientId,
          visitId: visitId,
          deferPersistence: canEdit,
          canEdit: canEdit,
          expandBody: expandField,
        );

        if (!useSideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              intakeColumn,
              const SizedBox(height: VisitPageTokens.sectionGap),
              healthCard,
            ],
          );
        }

        if (!expandField) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: intakeColumn),
              const SizedBox(width: VisitPageTokens.sectionGap),
              Expanded(flex: 2, child: healthCard),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: intakeColumn),
            const SizedBox(width: VisitPageTokens.sectionGap),
            Expanded(flex: 2, child: healthCard),
          ],
        );
      },
    );
  }

  Widget _complaintHistoryColumn({required bool expandField}) {
    final complaint = EncounterFieldCard(
      title: 'Complaint',
      titleIcon: Icons.speaker_notes_outlined,
      expandBody: expandField,
      embedTitleInToolbar: true,
      child: ClinicalNoteEditor(
        visitId: visitId,
        state: state,
        canEdit: canEdit,
        sections: const {ClinicalNoteSection.complaint},
        showSectionHeaders: false,
        expandField: expandField,
        useRichTextParagraph: true,
        removeBorder: true,
        showStaleBanner: true,
        showSaveBar: showClinicalNoteSaveBar,
        showEditButton: true,
        toolbarLeading: const EncounterToolbarTitle(title: 'Complaint', icon: Icons.speaker_notes_outlined),
        emptyStateIcon: Icons.speaker_notes_outlined,
        emptyStateText: 'Start entering the complaint',
      ),
    );

    final history = EncounterFieldCard(
      title: 'History',
      titleIcon: Icons.history_outlined,
      expandBody: expandField,
      embedTitleInToolbar: true,
      child: ClinicalNoteEditor(
        visitId: visitId,
        state: state,
        canEdit: canEdit,
        sections: const {ClinicalNoteSection.history},
        showSectionHeaders: false,
        expandField: expandField,
        useRichTextParagraph: true,
        removeBorder: true,
        showStaleBanner: false,
        showSaveBar: false,
        toolbarLeading: const EncounterToolbarTitle(title: 'History', icon: Icons.history_outlined),
        emptyStateIcon: Icons.history_outlined,
        emptyStateText: 'Start entering the history',
      ),
    );

    if (!expandField) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          complaint,
          const SizedBox(height: VisitPageTokens.sectionGap),
          history,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: complaint),
        const SizedBox(height: VisitPageTokens.sectionGap),
        Expanded(child: history),
      ],
    );
  }
}

/// Subjective content for the detail view.
class EncounterPhaseSubjectiveDetail extends StatelessWidget {
  const EncounterPhaseSubjectiveDetail({
    required this.visitId,
    required this.state,
    required this.canEdit,
    this.note,
    this.visit,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState? state;
  final bool canEdit;
  final VisitClinicalNote? note;
  final VisitDetail? visit;

  @override
  Widget build(BuildContext context) {
    if (canEdit && state != null) {
      return EncounterPhaseSubjective(visitId: visitId, state: state!, canEdit: true);
    }

    final patientId = visit?.patientId;
    final readOnlyColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EncounterFieldCard(
          title: 'Complaint',
          titleIcon: Icons.speaker_notes_outlined,
          child: EncounterDetailText(value: note?.complaint ?? ''),
        ),
        const SizedBox(height: VisitPageTokens.sectionGap),
        EncounterFieldCard(
          title: 'History',
          titleIcon: Icons.history_outlined,
          child: EncounterDetailText(value: note?.history ?? ''),
        ),
      ],
    );

    if (patientId == null || patientId.isEmpty) {
      return readOnlyColumn;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSideBySide = constraints.maxWidth >= 900;
        final healthCard = PatientHealthTrackingCard(patientId: patientId, canEdit: false);

        if (!useSideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              readOnlyColumn,
              const SizedBox(height: VisitPageTokens.sectionGap),
              healthCard,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: readOnlyColumn),
            const SizedBox(width: VisitPageTokens.sectionGap),
            Expanded(flex: 2, child: healthCard),
          ],
        );
      },
    );
  }
}
