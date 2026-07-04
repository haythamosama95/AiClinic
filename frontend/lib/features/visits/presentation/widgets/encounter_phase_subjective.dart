import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_patient_safety_panel.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_clinical_note_editor.dart';

/// Intake phase — complaint, history, and patient safety (014 US2).
class EncounterPhaseSubjective extends ConsumerWidget {
  const EncounterPhaseSubjective({
    required this.visitId,
    required this.state,
    required this.canEdit,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSideBySide = constraints.maxWidth >= 900;

        final intake = VisitClinicalNoteEditor(
          visitId: visitId,
          state: state,
          canEdit: canEdit,
          showStaleBanner: true,
          sections: const {ClinicalNoteSection.complaint, ClinicalNoteSection.history},
        );

        final safety = EncounterPatientSafetyPanel(
          visitId: visitId,
          patientId: state.visit.patientId,
          canEdit: canEdit,
        );

        if (!useSideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              intake,
              const SizedBox(height: AppSpacing.s6),
              safety,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: intake),
            const SizedBox(width: AppSpacing.s4),
            Expanded(flex: 2, child: safety),
          ],
        );
      },
    );
  }
}
