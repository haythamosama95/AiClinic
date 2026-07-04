import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_vital_signs_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_clinical_note_editor.dart';

/// Findings & Diagnosis phase — examination, diagnosis, vitals (014 US2).
class EncounterPhaseObjective extends ConsumerWidget {
  const EncounterPhaseObjective({
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

        final findings = VisitClinicalNoteEditor(
          visitId: visitId,
          state: state,
          canEdit: canEdit,
          showStaleBanner: true,
          sections: const {ClinicalNoteSection.examination, ClinicalNoteSection.diagnosis},
        );

        final vitals = EncounterVitalSignsCard(
          visitId: visitId,
          vitalSigns: state.visit.vitalSigns,
          predefinedVitalSigns: state.predefinedVitalSigns,
          canEdit: canEdit,
        );

        if (!useSideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              findings,
              const SizedBox(height: AppSpacing.s6),
              vitals,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: findings),
            const SizedBox(width: AppSpacing.s4),
            Expanded(flex: 2, child: vitals),
          ],
        );
      },
    );
  }
}
