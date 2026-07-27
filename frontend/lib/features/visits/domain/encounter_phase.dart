/// Encounter workspace phases (014) — view grouping over existing 013 fields.
enum EncounterPhase {
  context,
  subjective,
  objective,
  plan,
  review;

  /// Phases with editable documentation canvases (excludes Summary).
  static const documentationPhases = <EncounterPhase>[subjective, objective, plan];

  /// Guided stepper order (excludes Summary — opened via Finish Visit).
  static const stepperPhases = documentationPhases;

  /// All navigable phases including the read-only Summary view.
  static const ordered = <EncounterPhase>[subjective, objective, plan, review];

  bool get isDocumentation => documentationPhases.contains(this);

  bool get _isInStepper => stepperPhases.contains(this);

  /// Index within [stepperPhases]; [review] and excluded phases return [stepperPhases.length].
  int get stepperIndex {
    if (this == review || !_isInStepper) {
      return stepperPhases.length;
    }
    return stepperPhases.indexOf(this);
  }

  int get orderIndex => stepperIndex;

  EncounterPhase? get next {
    if (this == EncounterPhase.plan || this == EncounterPhase.review || !_isInStepper) {
      return null;
    }
    final idx = stepperIndex;
    if (idx >= stepperPhases.length - 1) {
      return null;
    }
    return stepperPhases[idx + 1];
  }

  EncounterPhase? get previous {
    if (this == EncounterPhase.subjective || this == EncounterPhase.review || !_isInStepper) {
      return null;
    }
    final idx = stepperIndex;
    if (idx <= 0) {
      return null;
    }
    return stepperPhases[idx - 1];
  }
}

/// Client-derived step badge state for the guided workspace (014 US4).
enum PhaseCompletionBadge { empty, hasContent, error }
