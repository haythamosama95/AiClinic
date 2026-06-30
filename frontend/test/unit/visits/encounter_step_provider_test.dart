import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../widget/visits/visit_encounter_test_support.dart';

void main() {
  group('deriveEncounterPhaseBadges', () {
    test('marks empty phases when no content exists', () {
      final badges = deriveEncounterPhaseBadges(sampleEncounterDocState());

      expect(badges[EncounterPhase.subjective], PhaseCompletionBadge.empty);
      expect(badges[EncounterPhase.objective], PhaseCompletionBadge.empty);
      expect(badges[EncounterPhase.plan], PhaseCompletionBadge.empty);
      expect(badges[EncounterPhase.review], PhaseCompletionBadge.empty);
    });

    test('marks subjective has-content when visit type is present', () {
      final visit = sampleEncounterVisit(visitType: 'Check-up');
      final badges = deriveEncounterPhaseBadges(sampleEncounterDocState(visit: visit));

      expect(badges[EncounterPhase.subjective], PhaseCompletionBadge.hasContent);
    });

    test('marks subjective has-content from draft complaint', () {
      final badges = deriveEncounterPhaseBadges(sampleEncounterDocState().copyWith(complaint: 'Fever'));

      expect(badges[EncounterPhase.subjective], PhaseCompletionBadge.hasContent);
    });

    test('marks objective has-content from vital signs', () {
      final visit = sampleEncounterVisit(
        vitalSigns: const [VisitVitalSign(id: 'v1', name: 'BP', value: '120/80', unit: 'mmHg')],
      );
      final badges = deriveEncounterPhaseBadges(sampleEncounterDocState(visit: visit));

      expect(badges[EncounterPhase.objective], PhaseCompletionBadge.hasContent);
    });

    test('marks error when a section exceeds max length', () {
      final oversized = 'x' * (kMaxClinicalSectionLength + 1);
      final badges = deriveEncounterPhaseBadges(sampleEncounterDocState().copyWith(diagnosis: oversized));

      expect(badges[EncounterPhase.objective], PhaseCompletionBadge.error);
      expect(badges[EncounterPhase.review], PhaseCompletionBadge.error);
    });

    test('marks review has-content when any clinical section has text', () {
      final badges = deriveEncounterPhaseBadges(sampleEncounterDocState().copyWith(plan: 'Rest and fluids'));

      expect(badges[EncounterPhase.review], PhaseCompletionBadge.hasContent);
      expect(badges[EncounterPhase.plan], PhaseCompletionBadge.hasContent);
    });
  });
}
