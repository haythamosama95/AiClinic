import 'package:flutter/material.dart';

/// Encounter workspace phases (014) — view grouping over existing 013 fields.
enum EncounterPhase {
  context,
  subjective,
  objective,
  plan,
  review;

  /// Phases with editable documentation canvases (excludes Review).
  static const documentationPhases = <EncounterPhase>[subjective, objective, plan];

  /// Full stepper order including the read-only Review step.
  static const ordered = <EncounterPhase>[subjective, objective, plan, review];

  bool get isDocumentation => index <= plan.index;

  String get label => switch (this) {
    context => 'Background',
    subjective => 'Intake',
    objective => 'Findings & Diagnosis',
    plan => 'Treatment',
    review => 'Summary',
  };

  String get abbr => switch (this) {
    context => 'BG',
    subjective => 'IN',
    objective => 'FD',
    plan => 'TX',
    review => 'SM',
  };

  IconData get icon => switch (this) {
    context => Icons.info_outline_rounded,
    subjective => Icons.chat_bubble_outline_rounded,
    objective => Icons.monitor_heart_outlined,
    plan => Icons.medical_services_outlined,
    review => Icons.summarize_outlined,
  };

  int get orderIndex => ordered.indexOf(this);

  EncounterPhase? get next => switch (this) {
    review => null,
    _ => ordered[orderIndex + 1],
  };

  EncounterPhase? get previous => switch (this) {
    subjective => null,
    _ => ordered[orderIndex - 1],
  };
}

/// Client-derived step badge state for the guided workspace (014 US4).
enum PhaseCompletionBadge { empty, hasContent, error }
