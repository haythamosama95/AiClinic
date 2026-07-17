import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/visit_encounter_test_support.dart';

void main() {
  group('deriveEncounterPhaseBadges', () {
    test('marks empty phases when no content exists', () {
      final badges = deriveEncounterPhaseBadges(sampleEncounterDocState());

      expect(badges[EncounterPhase.subjective], PhaseCompletionBadge.empty);
      expect(badges[EncounterPhase.objective], PhaseCompletionBadge.empty);
      expect(badges[EncounterPhase.plan], PhaseCompletionBadge.empty);
      expect(badges.containsKey(EncounterPhase.review), isFalse);
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
    });

    test('marks plan has-content when plan section has text', () {
      final badges = deriveEncounterPhaseBadges(sampleEncounterDocState().copyWith(plan: 'Rest and fluids'));

      expect(badges[EncounterPhase.plan], PhaseCompletionBadge.hasContent);
    });

    test('marks plan has-content from staged treatment plan draft', () {
      final badges = deriveEncounterPhaseBadges(
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

      expect(badges[EncounterPhase.plan], PhaseCompletionBadge.hasContent);
    });
  });

  group('encounterActivePhaseProvider', () {
    Future<VisitDetailViewState> completedVisitView() async {
      return VisitDetailViewState(
        visit: sampleEncounterVisit().copyWith(status: VisitStatus.completed),
        canEditDocumentation: true,
        hasBranchAccess: true,
        canUploadAttachments: true,
      );
    }

    Future<VisitDetailViewState> inProgressVisitView() async {
      return VisitDetailViewState(
        visit: sampleEncounterVisit(),
        canEditDocumentation: true,
        hasBranchAccess: true,
        canUploadAttachments: true,
      );
    }

    test('opens completed visits on Summary when visit detail is already cached', () async {
      final container = ProviderContainer(
        overrides: [visitDetailViewProvider(encounterTestVisitId).overrideWith((ref) => completedVisitView())],
      );
      addTearDown(container.dispose);

      await container.read(visitDetailViewProvider(encounterTestVisitId).future);

      expect(container.read(encounterActivePhaseProvider(encounterTestVisitId)), EncounterPhase.review);
    });

    test('opens completed visits on Summary after visit detail resolves', () async {
      final container = ProviderContainer(
        overrides: [visitDetailViewProvider(encounterTestVisitId).overrideWith((ref) => completedVisitView())],
      );
      addTearDown(container.dispose);

      container.read(encounterActivePhaseProvider(encounterTestVisitId));
      await container.read(visitDetailViewProvider(encounterTestVisitId).future);

      expect(container.read(encounterActivePhaseProvider(encounterTestVisitId)), EncounterPhase.review);
    });

    test('opens in-progress visits on Intake', () async {
      final container = ProviderContainer(
        overrides: [visitDetailViewProvider(encounterTestVisitId).overrideWith((ref) => inProgressVisitView())],
      );
      addTearDown(container.dispose);

      container.read(encounterActivePhaseProvider(encounterTestVisitId));
      await container.read(visitDetailViewProvider(encounterTestVisitId).future);

      expect(container.read(encounterActivePhaseProvider(encounterTestVisitId)), EncounterPhase.subjective);
    });

    test('preserves manual phase changes after initial load', () async {
      final container = ProviderContainer(
        overrides: [visitDetailViewProvider(encounterTestVisitId).overrideWith((ref) => completedVisitView())],
      );
      addTearDown(container.dispose);

      container.read(encounterActivePhaseProvider(encounterTestVisitId));
      await container.read(visitDetailViewProvider(encounterTestVisitId).future);
      container.read(encounterActivePhaseProvider(encounterTestVisitId).notifier).setPhase(EncounterPhase.plan);

      expect(container.read(encounterActivePhaseProvider(encounterTestVisitId)), EncounterPhase.plan);
    });
  });
}
