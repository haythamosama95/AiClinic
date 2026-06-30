import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_documentation_layout.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_assessment.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_context.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_objective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_plan.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_subjective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/patient_safety_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'visit_encounter_test_support.dart';

void main() {
  group('patient safety rail', () {
    testWidgets('renders degraded alerts and empty categories', (tester) async {
      await pumpEncounterWidget(tester, child: const PatientSafetyRail());

      expect(find.byKey(const Key('patient_safety_rail')), findsOneWidget);
      expect(find.byKey(const Key('patient_safety_alerts_line')), findsOneWidget);
      expect(find.text('Alerts: none documented'), findsOneWidget);
      expect(find.byKey(const Key('patient_safety_allergies')), findsOneWidget);
      expect(find.byKey(const Key('patient_safety_medications')), findsOneWidget);
      expect(find.byKey(const Key('patient_safety_conditions')), findsOneWidget);
      expect(find.byKey(const Key('patient_safety_last_vitals')), findsOneWidget);
    });

    testWidgets('is present alongside every documentation phase canvas', (tester) async {
      final visit = sampleEncounterVisit(visitType: 'Check-up');
      final state = sampleEncounterDocState(visit: visit);

      for (final phase in EncounterPhase.documentationPhases) {
        await pumpEncounterWidget(
          tester,
          docState: state,
          child: EncounterDocumentationLayout(activePhase: phase, phases: [_phaseWidget(phase, visit, state)]),
        );

        expect(find.byKey(const Key('patient_safety_rail')), findsOneWidget);
        expect(find.byKey(const Key('patient_safety_alerts_line')), findsOneWidget);
      }
    });
  });
}

Widget _phaseWidget(EncounterPhase phase, VisitDetail visit, VisitDocumentationState state) {
  return switch (phase) {
    EncounterPhase.context => EncounterPhaseContext(visit: visit),
    EncounterPhase.subjective => EncounterPhaseSubjective(visitId: encounterTestVisitId, state: state, canEdit: true),
    EncounterPhase.objective => EncounterPhaseObjective(
      visitId: encounterTestVisitId,
      state: state,
      canEdit: true,
      onRefresh: () {},
    ),
    EncounterPhase.assessment => EncounterPhaseAssessment(visitId: encounterTestVisitId, state: state, canEdit: true),
    EncounterPhase.plan => EncounterPhasePlan(
      visitId: encounterTestVisitId,
      state: state,
      canEdit: true,
      canUploadAttachments: true,
      onRefresh: () {},
    ),
    EncounterPhase.review => const SizedBox.shrink(),
  };
}
