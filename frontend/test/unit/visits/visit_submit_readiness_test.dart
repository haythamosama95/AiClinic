import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_submit_readiness.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/visit_encounter_test_support.dart';

List<dynamic> richDeltaBoldText(String text) => [
  {'insert': text, 'attributes': const {'bold': true}},
  {'insert': '\n'},
];

const List<dynamic> richDeltaEffectivelyEmpty = [
  {'insert': '\n'},
];

VisitDocumentationState richTextOnlyComplaintState({required List<dynamic> complaintDelta, String plainComplaint = ''}) {
  return sampleEncounterDocState().copyWith(
    complaint: plainComplaint,
    richTextDrafts: {ClinicalNoteSection.complaint: complaintDelta},
  );
}

VisitDocumentationState patientSafetyOnlyDocState() {
  return sampleEncounterDocState().copyWith(
    encounterDraft: buildVisitEncounterDraft(
      patientSafety: const PatientSafetyDraft(
        pendingAllergies: [PatientAllergy(id: 'draft:allergy-1', substance: 'Penicillin', reaction: 'Rash')],
      ),
    ),
  );
}

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

  group('visitHasPersistableDocumentation', () {
    test('trivial: false when all documentation is empty', () {
      expect(visitHasPersistableDocumentation(sampleEncounterDocState()), isFalse);
    });

    test('EDGE-001: ignores pending allergy draft alone', () {
      expect(visitHasPersistableDocumentation(patientSafetyOnlyDocState()), isFalse);
    });

    test('EDGE-007: false for formatting-only empty rich delta', () {
      final state = richTextOnlyComplaintState(complaintDelta: richDeltaEffectivelyEmpty);

      expect(visitHasPersistableDocumentation(state), isFalse);
    });

    test('advanced: true when complaint plain text is present', () {
      expect(
        visitHasPersistableDocumentation(sampleEncounterDocState().copyWith(complaint: 'Headache')),
        isTrue,
      );
    });
  });
}
