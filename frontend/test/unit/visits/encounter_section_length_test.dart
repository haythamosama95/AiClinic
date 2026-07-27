import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_submit_readiness_mapper.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/visit_encounter_test_support.dart';

void main() {
  const lengthErrorMessage = 'Each clinical note section must be 10,000 characters or fewer.';

  String oversizedText([int extra = 1]) => 'x' * (kMaxClinicalSectionLength + extra);

  group('EDGE-003 — Section length exceeds kMaxClinicalSectionLength', () {
    group('clinicalSectionLengthError', () {
      test('returns null when every section is at or below the limit', () {
        final atLimit = 'x' * kMaxClinicalSectionLength;

        expect(
          clinicalSectionLengthError(
            complaint: atLimit,
            history: '',
            examination: '',
            diagnosis: '',
            plan: '',
          ),
          isNull,
        );
      });

      test('returns error message when diagnosis exceeds the limit', () {
        expect(
          clinicalSectionLengthError(
            complaint: '',
            history: '',
            examination: '',
            diagnosis: oversizedText(),
            plan: '',
          ),
          lengthErrorMessage,
        );
      });

      test('returns error message for each clinical section field', () {
        for (final field in ['complaint', 'history', 'examination', 'diagnosis', 'plan']) {
          final sections = <String, String>{
            'complaint': '',
            'history': '',
            'examination': '',
            'diagnosis': '',
            'plan': '',
            field: oversizedText(),
          };

          expect(
            clinicalSectionLengthError(
              complaint: sections['complaint']!,
              history: sections['history']!,
              examination: sections['examination']!,
              diagnosis: sections['diagnosis']!,
              plan: sections['plan']!,
            ),
            lengthErrorMessage,
            reason: '$field over limit should block save',
          );
        }
      });
    });

    group('deriveEncounterPhaseBadges', () {
      test('marks subjective error when complaint exceeds max length', () {
        final badges = deriveEncounterPhaseBadges(sampleEncounterDocState().copyWith(complaint: oversizedText()));

        expect(badges[EncounterPhase.subjective], PhaseCompletionBadge.error);
        expect(badges[EncounterPhase.objective], PhaseCompletionBadge.empty);
        expect(badges[EncounterPhase.plan], PhaseCompletionBadge.empty);
      });

      test('marks subjective error when history exceeds max length', () {
        final badges = deriveEncounterPhaseBadges(sampleEncounterDocState().copyWith(history: oversizedText()));

        expect(badges[EncounterPhase.subjective], PhaseCompletionBadge.error);
      });

      test('marks objective error when examination exceeds max length', () {
        final badges = deriveEncounterPhaseBadges(sampleEncounterDocState().copyWith(examination: oversizedText()));

        expect(badges[EncounterPhase.objective], PhaseCompletionBadge.error);
        expect(badges[EncounterPhase.subjective], PhaseCompletionBadge.empty);
      });

      test('marks objective error when diagnosis exceeds max length', () {
        final badges = deriveEncounterPhaseBadges(sampleEncounterDocState().copyWith(diagnosis: oversizedText()));

        expect(badges[EncounterPhase.objective], PhaseCompletionBadge.error);
      });

      test('marks plan error when plan exceeds max length', () {
        final badges = deriveEncounterPhaseBadges(sampleEncounterDocState().copyWith(plan: oversizedText()));

        expect(badges[EncounterPhase.plan], PhaseCompletionBadge.error);
        expect(badges[EncounterPhase.subjective], PhaseCompletionBadge.empty);
        expect(badges[EncounterPhase.objective], PhaseCompletionBadge.empty);
      });

      test('does not mark error when section is exactly at max length', () {
        final atLimit = 'x' * kMaxClinicalSectionLength;
        final badges = deriveEncounterPhaseBadges(sampleEncounterDocState().copyWith(diagnosis: atLimit));

        expect(badges[EncounterPhase.objective], PhaseCompletionBadge.hasContent);
      });
    });

    group('evaluateVisitSubmitReadiness', () {
      test('excludes error phases from emptyPhases when diagnosis exceeds max length', () {
        final readiness = evaluateVisitSubmitReadinessFromState(sampleEncounterDocState().copyWith(diagnosis: oversizedText()));

        expect(readiness.hasMinimumDocumentation, isTrue);
        expect(readiness.emptyPhases, [EncounterPhase.subjective, EncounterPhase.plan]);
        expect(readiness.emptyPhases, isNot(contains(EncounterPhase.objective)));
      });

      test('still reports minimum documentation when only an oversized section has text', () {
        final readiness = evaluateVisitSubmitReadinessFromState(sampleEncounterDocState().copyWith(plan: oversizedText()));

        expect(readiness.hasMinimumDocumentation, isTrue);
        expect(readiness.emptyPhases, [EncounterPhase.subjective, EncounterPhase.objective]);
      });
    });
  });
}
