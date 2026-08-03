import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/domain/rich_text_draft_utils.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

typedef PhaseBadges = Map<EncounterPhase, PhaseCompletionBadge>;

/// Derives step badges from persisted visit data plus in-progress draft fields.
PhaseBadges deriveEncounterPhaseBadges(VisitDocumentationState state) {
  final effectiveVisit = state.effectiveVisit;

  return {for (final phase in EncounterPhase.stepperPhases) phase: _badgeForPhase(phase, state, effectiveVisit)};
}

PhaseCompletionBadge _badgeForPhase(EncounterPhase phase, VisitDocumentationState state, VisitDetail visit) {
  return switch (phase) {
    EncounterPhase.subjective => _subjectiveBadge(state, visit),
    EncounterPhase.objective => _findingsAndDiagnosisBadge(state),
    EncounterPhase.plan => _planBadge(state),
    EncounterPhase.review || EncounterPhase.billing || EncounterPhase.context => PhaseCompletionBadge.empty,
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
  if (_sectionHasContent(state, ClinicalNoteSection.complaint, state.complaint) ||
      _sectionHasContent(state, ClinicalNoteSection.history, state.history) ||
      _contextBadge(visit) == PhaseCompletionBadge.hasContent ||
      !state.encounterDraft.patientSafety.isEmpty) {
    return PhaseCompletionBadge.hasContent;
  }
  return PhaseCompletionBadge.empty;
}

PhaseCompletionBadge _findingsAndDiagnosisBadge(VisitDocumentationState state) {
  final visit = state.effectiveVisit;
  if (_sectionTooLong(state.examination) || _sectionTooLong(state.diagnosis)) {
    return PhaseCompletionBadge.error;
  }
  if (_sectionHasContent(state, ClinicalNoteSection.examination, state.examination) ||
      _sectionHasContent(state, ClinicalNoteSection.diagnosis, state.diagnosis) ||
      visit.vitalSigns.isNotEmpty) {
    return PhaseCompletionBadge.hasContent;
  }
  return PhaseCompletionBadge.empty;
}

PhaseCompletionBadge _planBadge(VisitDocumentationState state) {
  final visit = state.effectiveVisit;
  if (_sectionTooLong(state.plan)) {
    return PhaseCompletionBadge.error;
  }
  if (_sectionHasContent(state, ClinicalNoteSection.plan, state.plan) ||
      visit.treatmentPlans.isNotEmpty ||
      visit.investigations.isNotEmpty ||
      visit.attachments.isNotEmpty) {
    return PhaseCompletionBadge.hasContent;
  }
  return PhaseCompletionBadge.empty;
}

bool _sectionHasContent(VisitDocumentationState state, ClinicalNoteSection section, String value) {
  if (value.trim().isNotEmpty) {
    return true;
  }
  return !richDeltaIsEffectivelyEmpty(state.richTextDrafts[section]);
}

bool _sectionTooLong(String value) => value.length > kMaxClinicalSectionLength;

PhaseBadges _emptyBadges() => {for (final phase in EncounterPhase.stepperPhases) phase: PhaseCompletionBadge.empty};

/// Active encounter step for the guided workspace (014 US4).
final encounterActivePhaseProvider = NotifierProvider.autoDispose
    .family<EncounterActivePhaseNotifier, EncounterPhase, String>(EncounterActivePhaseNotifier.new);

class EncounterActivePhaseNotifier extends Notifier<EncounterPhase> {
  EncounterActivePhaseNotifier(this._visitId);

  final String _visitId;
  var _initialPhaseResolved = false;

  @override
  EncounterPhase build() {
    ref.listen(visitDocumentationProvider(_visitId), (previous, next) {
      if (_initialPhaseResolved) {
        return;
      }
      next.whenData((docState) {
        _initialPhaseResolved = true;
        if (docState.visit.status == VisitStatus.completed) {
          setPhase(EncounterPhase.review);
        }
      });
    }, fireImmediately: true);

    ref.listen(visitDetailViewProvider(_visitId), (previous, next) {
      if (_initialPhaseResolved) {
        return;
      }
      next.whenData((view) {
        _initialPhaseResolved = true;
        if (view.visit.status == VisitStatus.completed) {
          setPhase(EncounterPhase.review);
        }
      });
    }, fireImmediately: true);

    final visitAsync = ref.read(visitDetailViewProvider(_visitId));
    final docAsync = ref.read(visitDocumentationProvider(_visitId));
    final visitStatus = visitAsync.value?.visit.status ?? docAsync.value?.visit.status;

    final initialPhase = visitStatus == VisitStatus.completed ? EncounterPhase.review : EncounterPhase.subjective;
    if (visitStatus != null) {
      _initialPhaseResolved = true;
    }

    if (initialPhase == EncounterPhase.review) {
      Future.microtask(() {
        if (!ref.mounted) return;
        ref.read(visitDocumentationProvider(_visitId).notifier).prepareEncounterReview();
      });
    }

    return initialPhase;
  }

  void setPhase(EncounterPhase phase) {
    if (phase == EncounterPhase.review) {
      ref.read(visitDocumentationProvider(_visitId).notifier).prepareEncounterReview();
    }
    state = phase;
  }
}

/// Step completion badges derived from [visitDocumentationProvider].
final encounterPhaseBadgesProvider = Provider.autoDispose.family<PhaseBadges, String>((ref, visitId) {
  final docAsync = ref.watch(visitDocumentationProvider(visitId));
  return docAsync.when(data: deriveEncounterPhaseBadges, loading: _emptyBadges, error: (_, _) => _emptyBadges());
});
