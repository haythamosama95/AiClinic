import 'package:flutter/material.dart';

import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_encounter_step_placeholder.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_intake_section.dart';

/// Phase-specific body for the encounter documentation workspace.
class VisitEncounterStepContent extends StatelessWidget {
  const VisitEncounterStepContent({required this.visitId, required this.phase, required this.canEdit, super.key});

  final String visitId;
  final EncounterPhase phase;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    return switch (phase) {
      EncounterPhase.subjective => VisitIntakeSection(visitId: visitId, canEdit: canEdit),
      EncounterPhase.objective ||
      EncounterPhase.plan ||
      EncounterPhase.context ||
      EncounterPhase.review => VisitEncounterStepPlaceholder(phase: phase),
    };
  }
}
