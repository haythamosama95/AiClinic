import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_documentation_layout.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_objective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_plan.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_subjective.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'visit_encounter_test_support.dart';

void main() {
  group('encounter phase regrouping', () {
    testWidgets('maps every 013 field to exactly one phase', (tester) async {
      final visit = sampleEncounterVisit(
        visitType: 'Follow-up',
        vitalSigns: const [
          VisitVitalSign(id: 'h1', name: 'Height', value: '180', unit: 'cm'),
          VisitVitalSign(id: 'w1', name: 'Weight', value: '81', unit: 'kg'),
        ],
      );
      final state = sampleEncounterDocState(visit: visit);

      await pumpEncounterWidget(
        tester,
        docState: state,
        patientSafety: const PatientSafetyContext(),
        child: EncounterDocumentationLayout(
          phases: [
            EncounterPhaseSubjective(visitId: encounterTestVisitId, state: state, canEdit: true),
            EncounterPhaseObjective(visitId: encounterTestVisitId, state: state, canEdit: true, onRefresh: () {}),
            EncounterPhasePlan(
              visitId: encounterTestVisitId,
              state: state,
              canEdit: true,
              canUploadAttachments: true,
              onRefresh: () {},
            ),
          ],
        ),
      );

      for (final phaseKey in encounterPhaseKeys) {
        expect(find.byKey(phaseKey), findsOneWidget);
      }

      expectUniquePhaseAncestor(
        tester,
        const Key('encounter_context_visit_type'),
        const Key('encounter_phase_subjective'),
        otherPhaseKeysThan(const Key('encounter_phase_subjective')),
      );
      expectUniquePhaseAncestor(
        tester,
        const Key('clinical_note_complaint'),
        const Key('encounter_phase_subjective'),
        otherPhaseKeysThan(const Key('encounter_phase_subjective')),
      );
      expectUniquePhaseAncestor(
        tester,
        const Key('clinical_note_history'),
        const Key('encounter_phase_subjective'),
        otherPhaseKeysThan(const Key('encounter_phase_subjective')),
      );
      expectUniquePhaseAncestor(
        tester,
        const Key('vital_sign_add_button'),
        const Key('encounter_phase_objective'),
        otherPhaseKeysThan(const Key('encounter_phase_objective')),
      );
      expectUniquePhaseAncestor(
        tester,
        const Key('clinical_note_examination'),
        const Key('encounter_phase_objective'),
        otherPhaseKeysThan(const Key('encounter_phase_objective')),
      );
      expect(find.byKey(const Key('encounter_objective_bmi_chip')), findsOneWidget);
      expectUniquePhaseAncestor(
        tester,
        const Key('clinical_note_diagnosis'),
        const Key('encounter_phase_objective'),
        otherPhaseKeysThan(const Key('encounter_phase_objective')),
      );
      expectUniquePhaseAncestor(
        tester,
        const Key('clinical_note_plan'),
        const Key('encounter_phase_plan'),
        otherPhaseKeysThan(const Key('encounter_phase_plan')),
      );
      expectUniquePhaseAncestor(
        tester,
        const Key('treatment_plan_add_button'),
        const Key('encounter_phase_plan'),
        otherPhaseKeysThan(const Key('encounter_phase_plan')),
      );
      expectUniquePhaseAncestor(
        tester,
        const Key('investigation_add_button'),
        const Key('encounter_phase_plan'),
        otherPhaseKeysThan(const Key('encounter_phase_plan')),
      );
      expectUniquePhaseAncestor(
        tester,
        const Key('visit_attachment_upload_button'),
        const Key('encounter_phase_plan'),
        otherPhaseKeysThan(const Key('encounter_phase_plan')),
      );
    });
  });
}
