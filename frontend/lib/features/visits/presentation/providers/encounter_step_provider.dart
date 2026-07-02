import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

typedef PhaseBadges = Map<EncounterPhase, PhaseCompletionBadge>;

/// Derives step badges from persisted visit data plus in-progress draft fields.
PhaseBadges deriveEncounterPhaseBadges(VisitDocumentationState state) {
  final visit = state.visit;

  return {for (final phase in EncounterPhase.stepperPhases) phase: _badgeForPhase(phase, state, visit)};
}

PhaseCompletionBadge _badgeForPhase(EncounterPhase phase, VisitDocumentationState state, VisitDetail visit) {
  return switch (phase) {
    EncounterPhase.context => PhaseCompletionBadge.empty,
    EncounterPhase.subjective => _subjectiveBadge(state, visit),
    EncounterPhase.objective => _findingsAndDiagnosisBadge(state),
    EncounterPhase.plan => _planBadge(state),
    EncounterPhase.review => PhaseCompletionBadge.empty,
  };
}

PhaseCompletionBadge _contextBadge(VisitDetail visit) {
  final visitType = visit.visitType?.trim();
  if (visitType != null && visitType.isNotEmpty) {
    return PhaseCompletionBadge.hasContent;
  }
  return PhaseCompletionBadge.empty;
}

PhaseCompletionBadge _subjectiveBadge(VisitDocumentationState state, VisitDetail visit) {
  if (_sectionTooLong(state.complaint) || _sectionTooLong(state.history)) {
    return PhaseCompletionBadge.error;
  }
  if (_hasText(state.complaint) || _hasText(state.history) || _contextBadge(visit) == PhaseCompletionBadge.hasContent) {
    return PhaseCompletionBadge.hasContent;
  }
  return PhaseCompletionBadge.empty;
}

PhaseCompletionBadge _findingsAndDiagnosisBadge(VisitDocumentationState state) {
  if (_sectionTooLong(state.examination) || _sectionTooLong(state.diagnosis)) {
    return PhaseCompletionBadge.error;
  }
  if (_hasText(state.examination) || _hasText(state.diagnosis) || state.visit.vitalSigns.isNotEmpty) {
    return PhaseCompletionBadge.hasContent;
  }
  return PhaseCompletionBadge.empty;
}

PhaseCompletionBadge _planBadge(VisitDocumentationState state) {
  if (_sectionTooLong(state.plan)) {
    return PhaseCompletionBadge.error;
  }
  final visit = state.visit;
  if (_hasText(state.plan) ||
      visit.treatmentPlans.isNotEmpty ||
      visit.investigations.isNotEmpty ||
      visit.attachments.isNotEmpty) {
    return PhaseCompletionBadge.hasContent;
  }
  return PhaseCompletionBadge.empty;
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

bool _sectionTooLong(String value) => value.length > kMaxClinicalSectionLength;

PhaseBadges _emptyBadges() => {for (final phase in EncounterPhase.stepperPhases) phase: PhaseCompletionBadge.empty};

/// Active encounter step for the guided workspace (014 US4).
final encounterActivePhaseProvider = NotifierProvider.autoDispose
    .family<EncounterActivePhaseNotifier, EncounterPhase, String>(EncounterActivePhaseNotifier.new);

class EncounterActivePhaseNotifier extends Notifier<EncounterPhase> {
  EncounterActivePhaseNotifier(String _);

  @override
  EncounterPhase build() => EncounterPhase.subjective;

  void setPhase(EncounterPhase phase) {
    state = phase;
  }
}

/// Step completion badges derived from [visitDocumentationProvider].
final encounterPhaseBadgesProvider = Provider.autoDispose.family<PhaseBadges, String>((ref, visitId) {
  final docAsync = ref.watch(visitDocumentationProvider(visitId));
  return docAsync.when(data: deriveEncounterPhaseBadges, loading: _emptyBadges, error: (_, _) => _emptyBadges());
});
