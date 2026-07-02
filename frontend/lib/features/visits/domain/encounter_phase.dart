import 'package:flutter/material.dart';

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

  /// Index within [stepperPhases]; [review] returns [stepperPhases.length] (all steps complete).
  int get stepperIndex => this == review ? stepperPhases.length : stepperPhases.indexOf(this);

  int get orderIndex => stepperIndex;

  EncounterPhase? get next => switch (this) {
    plan || review => null,
    _ => stepperPhases[stepperIndex + 1],
  };

  EncounterPhase? get previous => switch (this) {
    subjective || review => null,
    _ => stepperPhases[stepperIndex - 1],
  };
}

/// Client-derived step badge state for the guided workspace (014 US4).
enum PhaseCompletionBadge { empty, hasContent, error }
