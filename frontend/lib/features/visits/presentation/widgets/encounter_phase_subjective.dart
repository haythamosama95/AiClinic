import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/clinical_note_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Subjective phase — Complaint and History (014 US2).
class EncounterPhaseSubjective extends ConsumerWidget {
  const EncounterPhaseSubjective({
    required this.visitId,
    required this.state,
    required this.canEdit,
    this.showClinicalNoteSaveBar = true,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final bool showClinicalNoteSaveBar;

  static const _sections = {ClinicalNoteSection.complaint, ClinicalNoteSection.history};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KeyedSubtree(
      key: const Key('encounter_phase_subjective'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const EncounterPhaseHeader(
            phase: EncounterPhase.subjective,
            description: 'Chief complaint and history of present illness',
          ),
          VisitSectionCard(
            kind: VisitPanelKind.clinicalNote,
            title: 'Subjective',
            child: ClinicalNoteEditor(
              visitId: visitId,
              state: state,
              canEdit: canEdit,
              sections: _sections,
              showStaleBanner: true,
              showSaveBar: showClinicalNoteSaveBar,
              showEditButton: true,
            ),
          ),
        ],
      ),
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
    super.key,
  });

  final String visitId;
  final VisitDocumentationState? state;
  final bool canEdit;
  final VisitClinicalNote? note;

  @override
  Widget build(BuildContext context) {
    if (canEdit && state != null) {
      return EncounterPhaseSubjective(visitId: visitId, state: state!, canEdit: true);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VisitDetailField(label: 'Complaint', value: note?.complaint ?? '', abbr: 'C'),
        VisitDetailField(label: 'History', value: note?.history ?? '', abbr: 'H'),
      ],
    );
  }
}
