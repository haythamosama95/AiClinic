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

/// Evaluates submit readiness from the current documentation state (draft-aware).
VisitSubmitReadiness evaluateVisitSubmitReadiness(VisitDocumentationState state) {
  final badges = deriveEncounterPhaseBadges(state);

  final emptyPhases = EncounterPhase.stepperPhases
      .where((phase) => badges[phase] == PhaseCompletionBadge.empty)
      .toList(growable: false);

  final hasMinimumDocumentation = badges.values.any((badge) => badge != PhaseCompletionBadge.empty);

  return VisitSubmitReadiness(hasMinimumDocumentation: hasMinimumDocumentation, emptyPhases: emptyPhases);
}
