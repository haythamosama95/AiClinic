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

/// Assessment phase — diagnosis section (014 US2).
class EncounterPhaseAssessment extends ConsumerWidget {
  const EncounterPhaseAssessment({
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

  static const _sections = {ClinicalNoteSection.diagnosis};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KeyedSubtree(
      key: const Key('encounter_phase_assessment'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const EncounterPhaseHeader(
            phase: EncounterPhase.assessment,
            description: 'Clinical assessment and diagnosis',
          ),
          VisitSectionCard(
            kind: VisitPanelKind.clinicalNote,
            title: 'Diagnosis',
            child: ClinicalNoteEditor(
              visitId: visitId,
              state: state,
              canEdit: canEdit,
              sections: _sections,
              showStaleBanner: false,
              showSaveBar: showClinicalNoteSaveBar,
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only assessment content for the detail view.
class EncounterPhaseAssessmentReadOnly extends StatelessWidget {
  const EncounterPhaseAssessmentReadOnly({
    required this.visitId,
    required this.state,
    required this.canEdit,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    return ClinicalNoteEditor(
      visitId: visitId,
      state: state,
      canEdit: canEdit,
      sections: EncounterPhaseAssessment._sections,
      showSaveBar: canEdit,
    );
  }
}

/// Read-only assessment from persisted visit data only.
class EncounterPhaseAssessmentFromVisit extends StatelessWidget {
  const EncounterPhaseAssessmentFromVisit({required this.note, super.key});

  final VisitClinicalNote? note;

  @override
  Widget build(BuildContext context) {
    return VisitDetailField(label: 'Diagnosis', value: note?.diagnosis ?? '', abbr: 'D');
  }
}
