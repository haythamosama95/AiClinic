import 'package:ai_clinic/core/ui/rich_text/rich_text_delta_utils.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/visit_submit_readiness.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_submit_readiness_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/visit_encounter_test_support.dart';

/// Quill delta JSON for formatted text without a synced plain-text field (EDGE-002).
List<dynamic> richDeltaBoldText(String text) => [
  {'insert': text, 'attributes': const {'bold': true}},
  {'insert': '\n'},
];

/// Default empty Quill document after all text is removed (EDGE-007).
const List<dynamic> richDeltaEffectivelyEmpty = [
  {'insert': '\n'},
];

VisitDocumentationState richTextOnlyComplaintState({required List<dynamic> complaintDelta, String plainComplaint = ''}) {
  return sampleEncounterDocState().copyWith(
    complaint: plainComplaint,
    richTextDrafts: {ClinicalNoteSection.complaint: complaintDelta},
  );
}

class _StaticEncounterDocNotifier extends VisitDocumentationNotifier {
  _StaticEncounterDocNotifier(this._initialState) : super(encounterTestVisitId);

  final VisitDocumentationState _initialState;

  @override
  Future<VisitDocumentationState> build() async => _initialState;
}

void main() {
  group('plainTextFromRichDelta', () {
    test('returns empty string for null delta', () {
      expect(plainTextFromRichDelta(null), '');
    });

    test('returns empty string for effectively empty delta', () {
      expect(plainTextFromRichDelta(richDeltaEffectivelyEmpty), '');
    });

    test('extracts plain text from formatted delta', () {
      expect(plainTextFromRichDelta(richDeltaBoldText('Headache')), 'Headache');
    });

    test('strips trailing newline from Quill document', () {
      const deltaWithTrailingNewline = [
        {'insert': 'Line one\nLine two'},
        {'insert': '\n'},
      ];
      expect(plainTextFromRichDelta(deltaWithTrailingNewline), 'Line one\nLine two');
    });
  });

  group('richDeltaIsEffectivelyEmpty', () {
    test('treats null and empty list as empty', () {
      expect(richDeltaIsEffectivelyEmpty(null), isTrue);
      expect(richDeltaIsEffectivelyEmpty(const []), isTrue);
    });

    test('treats lone newline insert without attributes as empty (EDGE-007)', () {
      expect(richDeltaIsEffectivelyEmpty(richDeltaEffectivelyEmpty), isTrue);
    });

    test('treats lone formatted newline insert as empty', () {
      const formattedBlankLine = [
        {'insert': '\n', 'attributes': {'header': 1}},
      ];
      expect(richDeltaIsEffectivelyEmpty(formattedBlankLine), isTrue);
    });

    test('treats formatted text delta as non-empty', () {
      expect(richDeltaIsEffectivelyEmpty(richDeltaBoldText('Headache')), isFalse);
    });
  });

  group('prepareEncounterReview plain-text sync', () {
    test('EDGE-002: syncs complaint plain text from rich delta when plain field is empty', () async {
      final initial = richTextOnlyComplaintState(complaintDelta: richDeltaBoldText('Headache'));
      final container = ProviderContainer(
        overrides: [
          visitDocumentationProvider(encounterTestVisitId).overrideWith(
            () => _StaticEncounterDocNotifier(initial),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(visitDocumentationProvider(encounterTestVisitId).future);

      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);
      final synced = notifier.prepareEncounterReview();

      expect(synced?.complaint, 'Headache');
      expect(container.read(visitDocumentationProvider(encounterTestVisitId)).value?.complaint, 'Headache');
    });

    test('preserves existing plain text when complaint already has content', () async {
      final initial = richTextOnlyComplaintState(
        plainComplaint: 'Cached plain',
        complaintDelta: richDeltaBoldText('Rich only'),
      );
      final container = ProviderContainer(
        overrides: [
          visitDocumentationProvider(encounterTestVisitId).overrideWith(
            () => _StaticEncounterDocNotifier(initial),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(visitDocumentationProvider(encounterTestVisitId).future);

      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);
      final synced = notifier.prepareEncounterReview();

      expect(synced?.complaint, 'Cached plain');
    });

    test('EDGE-007: leaves complaint empty when rich delta is effectively empty', () async {
      final initial = richTextOnlyComplaintState(complaintDelta: richDeltaEffectivelyEmpty);
      final container = ProviderContainer(
        overrides: [
          visitDocumentationProvider(encounterTestVisitId).overrideWith(
            () => _StaticEncounterDocNotifier(initial),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(visitDocumentationProvider(encounterTestVisitId).future);

      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);
      final synced = notifier.prepareEncounterReview();

      expect(synced?.complaint, '');
    });

    test('invokes registered clinical-note flush callbacks before syncing', () async {
      var flushCount = 0;
      final initial = richTextOnlyComplaintState(complaintDelta: richDeltaBoldText('Headache'));
      final container = ProviderContainer(
        overrides: [
          visitDocumentationProvider(encounterTestVisitId).overrideWith(
            () => _StaticEncounterDocNotifier(initial),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(visitDocumentationProvider(encounterTestVisitId).future);

      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);
      notifier.registerClinicalNoteFlush(() => flushCount++);
      notifier.prepareEncounterReview();

      expect(flushCount, 1);
    });
  });

  group('submit readiness with rich deltas', () {
    test('EDGE-002: rich-text-only complaint counts before plain-text sync', () {
      final state = richTextOnlyComplaintState(complaintDelta: richDeltaBoldText('Headache'));

      final readiness = evaluateVisitSubmitReadinessFromState(state);
      final badges = deriveEncounterPhaseBadges(state);

      expect(readiness.hasMinimumDocumentation, isTrue);
      expect(readiness.emptyPhases, [EncounterPhase.objective, EncounterPhase.plan]);
      expect(badges[EncounterPhase.subjective], PhaseCompletionBadge.hasContent);
    });

    test('EDGE-002: after prepareEncounterReview rich-text-only complaint still allows submit', () async {
      final initial = richTextOnlyComplaintState(complaintDelta: richDeltaBoldText('Headache'));
      final container = ProviderContainer(
        overrides: [
          visitDocumentationProvider(encounterTestVisitId).overrideWith(
            () => _StaticEncounterDocNotifier(initial),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(visitDocumentationProvider(encounterTestVisitId).future);

      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);
      final synced = notifier.prepareEncounterReview()!;
      final readiness = evaluateVisitSubmitReadinessFromState(synced);

      expect(readiness.hasMinimumDocumentation, isTrue);
      expect(readiness.emptyPhases, [EncounterPhase.objective, EncounterPhase.plan]);
    });

    test('EDGE-007: effectively empty rich delta blocks submit and shows empty badge', () {
      final state = richTextOnlyComplaintState(complaintDelta: richDeltaEffectivelyEmpty);

      final readiness = evaluateVisitSubmitReadinessFromState(state);
      final badges = deriveEncounterPhaseBadges(state);

      expect(readiness.hasMinimumDocumentation, isFalse);
      expect(readiness.emptyPhases, EncounterPhase.stepperPhases);
      expect(badges[EncounterPhase.subjective], PhaseCompletionBadge.empty);
    });

    test('EDGE-007: visitHasPersistableDocumentation is false for formatting-only empty delta', () {
      final state = richTextOnlyComplaintState(complaintDelta: richDeltaEffectivelyEmpty);

      expect(visitHasPersistableDocumentationFromState(state), isFalse);
    });
  });
}
