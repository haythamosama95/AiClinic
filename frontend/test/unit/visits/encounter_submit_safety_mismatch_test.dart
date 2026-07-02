import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_submit_readiness.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../widget/visits/visit_encounter_test_support.dart';

VisitDocumentationState _patientSafetyOnlyDocState() {
  return sampleEncounterDocState().copyWith(
    encounterDraft: const VisitEncounterDraft(
      patientSafety: PatientSafetyDraft(
        pendingAllergies: [
          PatientAllergy(id: 'draft:allergy-1', substance: 'Penicillin', reaction: 'Rash'),
        ],
      ),
    ),
  );
}

void main() {
  group('EDGE-001 — Patient-safety-only submit (FE/BE mismatch)', () {
    test('visitHasPersistableDocumentation ignores pending allergy draft', () {
      expect(visitHasPersistableDocumentation(_patientSafetyOnlyDocState()), isFalse);
    });

    test('evaluateVisitSubmitReadiness blocks submit when only allergy is staged', () {
      final readiness = evaluateVisitSubmitReadiness(_patientSafetyOnlyDocState());

      expect(readiness.hasMinimumDocumentation, isFalse);
      expect(readiness.emptyPhases, [EncounterPhase.objective, EncounterPhase.plan]);
    });

    test('subjective phase badge still reflects patient safety draft content', () {
      final badges = deriveEncounterPhaseBadges(_patientSafetyOnlyDocState());

      expect(badges[EncounterPhase.subjective], PhaseCompletionBadge.hasContent);
      expect(badges[EncounterPhase.objective], PhaseCompletionBadge.empty);
      expect(badges[EncounterPhase.plan], PhaseCompletionBadge.empty);
    });

    test('clinical documentation still allows submit after BUG-001 alignment', () {
      final readiness = evaluateVisitSubmitReadiness(
        _patientSafetyOnlyDocState().copyWith(complaint: 'Seasonal allergy follow-up'),
      );

      expect(readiness.hasMinimumDocumentation, isTrue);
      expect(readiness.emptyPhases, [EncounterPhase.objective, EncounterPhase.plan]);
    });
  });
}
