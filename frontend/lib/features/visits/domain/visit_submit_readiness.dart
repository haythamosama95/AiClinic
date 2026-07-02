import 'package:ai_clinic/core/ui/widgets/input/app_paragraph_field.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

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
bool visitHasPersistableDocumentation(VisitDocumentationState state) {
  final visit = state.effectiveVisit;

  if (_clinicalNoteSectionHasContent(state, ClinicalNoteSection.complaint, state.complaint) ||
      _clinicalNoteSectionHasContent(state, ClinicalNoteSection.history, state.history) ||
      _clinicalNoteSectionHasContent(state, ClinicalNoteSection.examination, state.examination) ||
      _clinicalNoteSectionHasContent(state, ClinicalNoteSection.diagnosis, state.diagnosis) ||
      _clinicalNoteSectionHasContent(state, ClinicalNoteSection.plan, state.plan)) {
    return true;
  }

  if (visit.vitalSigns.isNotEmpty ||
      visit.investigations.isNotEmpty ||
      visit.treatmentPlans.isNotEmpty ||
      visit.attachments.isNotEmpty) {
    return true;
  }

  return visit.pendingInvestigations.any((investigation) => investigation.hasResult) ||
      state.encounterDraft.investigationResults.values.any((result) => result.trim().isNotEmpty);
}

bool _clinicalNoteSectionHasContent(VisitDocumentationState state, ClinicalNoteSection section, String value) {
  if (value.trim().isNotEmpty) {
    return true;
  }
  return !richDeltaIsEffectivelyEmpty(state.richTextDrafts[section]);
}

/// Evaluates submit readiness from the current documentation state (draft-aware).
VisitSubmitReadiness evaluateVisitSubmitReadiness(VisitDocumentationState state) {
  final badges = deriveEncounterPhaseBadges(state);

  final emptyPhases = EncounterPhase.stepperPhases
      .where((phase) => badges[phase] == PhaseCompletionBadge.empty)
      .toList(growable: false);

  final hasMinimumDocumentation = visitHasPersistableDocumentation(state);

  return VisitSubmitReadiness(hasMinimumDocumentation: hasMinimumDocumentation, emptyPhases: emptyPhases);
}
