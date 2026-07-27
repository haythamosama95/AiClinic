import 'package:ai_clinic/core/ui/rich_text/rich_text_delta_utils.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/visit_submit_readiness.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Builds plain submit-readiness inputs from presentation state.
VisitSubmitReadinessInput visitSubmitReadinessInputFromState(VisitDocumentationState state) {
  final visit = state.effectiveVisit;

  return VisitSubmitReadinessInput(
    sectionHasContent: {
      for (final section in ClinicalNoteSection.values)
        section: _clinicalNoteSectionHasContent(state, section),
    },
    vitalSignCount: visit.vitalSigns.length,
    investigationCount: visit.investigations.length,
    treatmentPlanCount: visit.treatmentPlans.length,
    attachmentCount: visit.attachments.length,
    hasPendingInvestigationResult: visit.pendingInvestigations.any((investigation) => investigation.hasResult),
    hasDraftInvestigationResult:
        state.encounterDraft.investigationResults.values.any((result) => result.trim().isNotEmpty),
    phaseBadges: deriveEncounterPhaseBadges(state),
  );
}

/// Evaluates submit readiness from the current documentation state (draft-aware).
VisitSubmitReadiness evaluateVisitSubmitReadinessFromState(VisitDocumentationState state) {
  return evaluateVisitSubmitReadiness(visitSubmitReadinessInputFromState(state));
}

/// Whether the visit has persistable documentation per backend `visit_has_documentation`.
bool visitHasPersistableDocumentationFromState(VisitDocumentationState state) {
  return visitHasPersistableDocumentation(visitSubmitReadinessInputFromState(state));
}

bool _clinicalNoteSectionHasContent(VisitDocumentationState state, ClinicalNoteSection section) {
  final value = switch (section) {
    ClinicalNoteSection.complaint => state.complaint,
    ClinicalNoteSection.history => state.history,
    ClinicalNoteSection.examination => state.examination,
    ClinicalNoteSection.diagnosis => state.diagnosis,
    ClinicalNoteSection.plan => state.plan,
  };

  if (value.trim().isNotEmpty) {
    return true;
  }
  return !richDeltaIsEffectivelyEmpty(state.richTextDrafts[section]);
}
