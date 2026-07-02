import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_submit_readiness.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../widget/visits/visit_encounter_test_support.dart';

void main() {
  group('evaluateVisitSubmitReadiness', () {
    test('all phases empty blocks submit', () {
      final readiness = evaluateVisitSubmitReadiness(sampleEncounterDocState());

      expect(readiness.hasMinimumDocumentation, isFalse);
      expect(readiness.emptyPhases, EncounterPhase.stepperPhases);
    });

    test('one filled clinical note allows submit and warns about empty phases', () {
      final readiness = evaluateVisitSubmitReadiness(sampleEncounterDocState().copyWith(complaint: 'Headache'));

      expect(readiness.hasMinimumDocumentation, isTrue);
      expect(readiness.emptyPhases, [EncounterPhase.objective, EncounterPhase.plan]);
    });

    test('all phases filled has no warnings', () {
      final readiness = evaluateVisitSubmitReadiness(
        sampleEncounterDocState().copyWith(
          complaint: 'Headache',
          history: 'Two days',
          examination: 'Normal',
          diagnosis: 'Tension headache',
          plan: 'Rest',
        ),
      );

      expect(readiness.hasMinimumDocumentation, isTrue);
      expect(readiness.emptyPhases, isEmpty);
      expect(readiness.hasEmptySectionWarnings, isFalse);
    });

    test('structured treatment plan draft alone allows submit and warns about other phases', () {
      final readiness = evaluateVisitSubmitReadiness(
        sampleEncounterDocState().copyWith(
          encounterDraft: VisitEncounterDraft(
            pendingTreatmentPlans: [
              TreatmentPlanItem(
                id: 'draft:1',
                visitId: encounterTestVisitId,
                patientId: encounterTestPatientId,
                medicationName: 'Ibuprofen',
                dosage: '400mg',
                frequency: 'daily',
                duration: '5 days',
              ),
            ],
          ),
        ),
      );

      expect(readiness.hasMinimumDocumentation, isTrue);
      expect(readiness.emptyPhases, [EncounterPhase.subjective, EncounterPhase.objective]);
    });

    test('vital sign alone allows submit and warns about other phases', () {
      final visit = sampleEncounterVisit(
        vitalSigns: const [VisitVitalSign(id: 'v1', name: 'BP', value: '120/80', unit: 'mmHg')],
      );
      final readiness = evaluateVisitSubmitReadiness(sampleEncounterDocState(visit: visit));

      expect(readiness.hasMinimumDocumentation, isTrue);
      expect(readiness.emptyPhases, [EncounterPhase.subjective, EncounterPhase.plan]);
    });
  });
}
