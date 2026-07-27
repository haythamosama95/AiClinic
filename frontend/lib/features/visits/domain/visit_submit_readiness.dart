import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:flutter/foundation.dart';

/// Plain inputs for evaluating visit submit readiness without presentation-layer state.
@immutable
class VisitSubmitReadinessInput {
  const VisitSubmitReadinessInput({
    required this.sectionHasContent,
    required this.vitalSignCount,
    required this.investigationCount,
    required this.treatmentPlanCount,
    required this.attachmentCount,
    required this.hasPendingInvestigationResult,
    required this.hasDraftInvestigationResult,
    required this.phaseBadges,
  });

  /// Whether each clinical note section has plain or rich-text content.
  final Map<ClinicalNoteSection, bool> sectionHasContent;

  final int vitalSignCount;
  final int investigationCount;
  final int treatmentPlanCount;
  final int attachmentCount;
  final bool hasPendingInvestigationResult;
  final bool hasDraftInvestigationResult;
  final Map<EncounterPhase, PhaseCompletionBadge> phaseBadges;
}

/// Result of evaluating whether a visit is ready to submit.
class VisitSubmitReadiness {
  const VisitSubmitReadiness({required this.hasMinimumDocumentation, required this.emptyPhases});

  /// Whether at least one encounter phase contains entered documentation.
  final bool hasMinimumDocumentation;

  /// Encounter phases with no entered content.
  final List<EncounterPhase> emptyPhases;

  bool get hasEmptySectionWarnings => emptyPhases.isNotEmpty;
}

/// Whether the visit has persistable documentation per backend `visit_has_documentation`.
///
/// Excludes patient-safety-only edits and visit-type metadata so submit validation
/// matches the `complete_visit` RPC.
bool visitHasPersistableDocumentation(VisitSubmitReadinessInput input) {
  if (input.sectionHasContent.values.any((hasContent) => hasContent)) {
    return true;
  }

  if (input.vitalSignCount > 0 ||
      input.investigationCount > 0 ||
      input.treatmentPlanCount > 0 ||
      input.attachmentCount > 0) {
    return true;
  }

  return input.hasPendingInvestigationResult || input.hasDraftInvestigationResult;
}

/// Evaluates submit readiness from plain documentation inputs (draft-aware values included).
VisitSubmitReadiness evaluateVisitSubmitReadiness(VisitSubmitReadinessInput input) {
  final emptyPhases = EncounterPhase.stepperPhases
      .where((phase) => input.phaseBadges[phase] == PhaseCompletionBadge.empty)
      .toList(growable: false);

  final hasMinimumDocumentation = visitHasPersistableDocumentation(input);

  return VisitSubmitReadiness(hasMinimumDocumentation: hasMinimumDocumentation, emptyPhases: emptyPhases);
}
