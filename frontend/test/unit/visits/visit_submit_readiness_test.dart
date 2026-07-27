import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/visit_submit_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

VisitSubmitReadinessInput _readinessInput({
  Map<ClinicalNoteSection, bool>? sectionHasContent,
  int vitalSignCount = 0,
  int investigationCount = 0,
  int treatmentPlanCount = 0,
  int attachmentCount = 0,
  bool hasPendingInvestigationResult = false,
  bool hasDraftInvestigationResult = false,
  Map<EncounterPhase, PhaseCompletionBadge>? phaseBadges,
}) {
  return VisitSubmitReadinessInput(
    sectionHasContent: sectionHasContent ??
        {
          for (final section in ClinicalNoteSection.values) section: false,
        },
    vitalSignCount: vitalSignCount,
    investigationCount: investigationCount,
    treatmentPlanCount: treatmentPlanCount,
    attachmentCount: attachmentCount,
    hasPendingInvestigationResult: hasPendingInvestigationResult,
    hasDraftInvestigationResult: hasDraftInvestigationResult,
    phaseBadges: phaseBadges ??
        {
          for (final phase in EncounterPhase.stepperPhases) phase: PhaseCompletionBadge.empty,
        },
  );
}

void main() {
  group('evaluateVisitSubmitReadiness', () {
    test('all phases empty blocks submit', () {
      final readiness = evaluateVisitSubmitReadiness(_readinessInput());

      expect(readiness.hasMinimumDocumentation, isFalse);
      expect(readiness.emptyPhases, EncounterPhase.stepperPhases);
    });

    test('one filled clinical note allows submit and warns about empty phases', () {
      final readiness = evaluateVisitSubmitReadiness(
        _readinessInput(
          sectionHasContent: {
            ClinicalNoteSection.complaint: true,
            ClinicalNoteSection.history: false,
            ClinicalNoteSection.examination: false,
            ClinicalNoteSection.diagnosis: false,
            ClinicalNoteSection.plan: false,
          },
          phaseBadges: {
            EncounterPhase.subjective: PhaseCompletionBadge.hasContent,
            EncounterPhase.objective: PhaseCompletionBadge.empty,
            EncounterPhase.plan: PhaseCompletionBadge.empty,
          },
        ),
      );

      expect(readiness.hasMinimumDocumentation, isTrue);
      expect(readiness.emptyPhases, [EncounterPhase.objective, EncounterPhase.plan]);
    });

    test('all phases filled has no warnings', () {
      final readiness = evaluateVisitSubmitReadiness(
        _readinessInput(
          sectionHasContent: {
            for (final section in ClinicalNoteSection.values) section: true,
          },
          phaseBadges: {
            for (final phase in EncounterPhase.stepperPhases) phase: PhaseCompletionBadge.hasContent,
          },
        ),
      );

      expect(readiness.hasMinimumDocumentation, isTrue);
      expect(readiness.emptyPhases, isEmpty);
      expect(readiness.hasEmptySectionWarnings, isFalse);
    });

    test('structured treatment plan draft alone allows submit and warns about other phases', () {
      final readiness = evaluateVisitSubmitReadiness(
        _readinessInput(
          treatmentPlanCount: 1,
          phaseBadges: {
            EncounterPhase.subjective: PhaseCompletionBadge.empty,
            EncounterPhase.objective: PhaseCompletionBadge.empty,
            EncounterPhase.plan: PhaseCompletionBadge.hasContent,
          },
        ),
      );

      expect(readiness.hasMinimumDocumentation, isTrue);
      expect(readiness.emptyPhases, [EncounterPhase.subjective, EncounterPhase.objective]);
    });

    test('vital sign alone allows submit and warns about other phases', () {
      final readiness = evaluateVisitSubmitReadiness(
        _readinessInput(
          vitalSignCount: 1,
          phaseBadges: {
            EncounterPhase.subjective: PhaseCompletionBadge.empty,
            EncounterPhase.objective: PhaseCompletionBadge.hasContent,
            EncounterPhase.plan: PhaseCompletionBadge.empty,
          },
        ),
      );

      expect(readiness.hasMinimumDocumentation, isTrue);
      expect(readiness.emptyPhases, [EncounterPhase.subjective, EncounterPhase.plan]);
    });
  });
}
