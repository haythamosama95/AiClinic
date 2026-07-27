import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';

/// Presentation metadata for [EncounterPhase] (icons, labels, abbreviations).
extension EncounterPhasePresentation on EncounterPhase {
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      EncounterPhase.context => l10n.encounterPhaseBackground,
      EncounterPhase.subjective => l10n.encounterPhaseIntake,
      EncounterPhase.objective => l10n.encounterPhaseFindingsDiagnosis,
      EncounterPhase.plan => l10n.encounterPhaseTreatment,
      EncounterPhase.review => l10n.encounterPhaseSummary,
    };
  }

  String get abbr => switch (this) {
    EncounterPhase.context => 'BG',
    EncounterPhase.subjective => 'IN',
    EncounterPhase.objective => 'FD',
    EncounterPhase.plan => 'TX',
    EncounterPhase.review => 'SM',
  };

  IconData get icon => switch (this) {
    EncounterPhase.context => Icons.info_outline_rounded,
    EncounterPhase.subjective => Icons.chat_bubble_outline_rounded,
    EncounterPhase.objective => Icons.monitor_heart_outlined,
    EncounterPhase.plan => Icons.medical_services_outlined,
    EncounterPhase.review => Icons.summarize_outlined,
  };
}
