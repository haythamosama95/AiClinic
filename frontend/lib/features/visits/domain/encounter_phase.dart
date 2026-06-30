/// Encounter workspace phases (014) — view grouping over existing 013 fields.
enum EncounterPhase {
  context,
  subjective,
  objective,
  assessment,
  plan,
  review;

  /// Phases with editable documentation canvases (excludes Review).
  static const documentationPhases = <EncounterPhase>[context, subjective, objective, assessment, plan];

  /// Full stepper order including the read-only Review step.
  static const ordered = <EncounterPhase>[context, subjective, objective, assessment, plan, review];

  bool get isDocumentation => index <= plan.index;

  String get label => switch (this) {
    context => 'Context',
    subjective => 'Subjective',
    objective => 'Objective',
    assessment => 'Assessment',
    plan => 'Plan',
    review => 'Review',
  };

  String get abbr => switch (this) {
    context => 'CTX',
    subjective => 'S',
    objective => 'O',
    assessment => 'A',
    plan => 'P',
    review => 'R',
  };

  int get orderIndex => ordered.indexOf(this);

  EncounterPhase? get next => switch (this) {
    review => null,
    _ => ordered[orderIndex + 1],
  };

  EncounterPhase? get previous => switch (this) {
    context => null,
    _ => ordered[orderIndex - 1],
  };
}

/// Client-derived step badge state for the guided workspace (014 US4).
enum PhaseCompletionBadge { empty, hasContent, error }
