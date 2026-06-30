import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Persistent read-only patient safety surface (014 US3 / FR-010–012).
///
/// P1 degrades to empty categories plus an alerts affordance until structured
/// patient safety records land in US6.
class PatientSafetyRail extends StatelessWidget {
  const PatientSafetyRail({this.phase, super.key});

  /// Optional active phase for semantics; rail content is the same on every phase.
  final EncounterPhase? phase;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Semantics(
      label: phase == null ? 'Patient safety context' : 'Patient safety context for ${phase!.label}',
      child: AppNotchedCard(
        key: const Key('patient_safety_rail'),
        titleIcon: Icons.health_and_safety_outlined,
        title: Text('Safety', style: theme.title(size: 15)),
        description: Text('Read-only patient context', style: theme.caption(size: 11.5)),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(SpacingTokens.md, 0, SpacingTokens.md, SpacingTokens.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SafetyAlertsLine(theme: theme),
              const SizedBox(height: SpacingTokens.md),
              _SafetyCategory(
                key: const Key('patient_safety_allergies'),
                icon: Icons.warning_amber_outlined,
                label: 'Allergies',
                emptyMessage: 'No allergies recorded.',
              ),
              const SizedBox(height: SpacingTokens.sm),
              _SafetyCategory(
                key: const Key('patient_safety_medications'),
                icon: Icons.medication_outlined,
                label: 'Current medications',
                emptyMessage: 'No current medications recorded.',
              ),
              const SizedBox(height: SpacingTokens.sm),
              _SafetyCategory(
                key: const Key('patient_safety_conditions'),
                icon: Icons.favorite_border,
                label: 'Chronic conditions',
                emptyMessage: 'No chronic conditions recorded.',
              ),
              const SizedBox(height: SpacingTokens.sm),
              _SafetyCategory(
                key: const Key('patient_safety_last_vitals'),
                icon: Icons.monitor_heart_outlined,
                label: 'Last vitals',
                emptyMessage: 'No prior vitals on file.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SafetyAlertsLine extends StatelessWidget {
  const _SafetyAlertsLine({required this.theme});

  final VisitTheme theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('patient_safety_alerts_line'),
      decoration: BoxDecoration(
        color: theme.tile,
        borderRadius: BorderRadius.circular(theme.tileRadius),
        border: Border.all(color: theme.hairlineSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.sm + 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.notifications_none_outlined, size: 16, color: theme.mutedInk),
            const SizedBox(width: SpacingTokens.sm),
            Expanded(
              child: Text('Alerts: none documented', style: theme.caption(color: theme.mutedInk)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyCategory extends StatelessWidget {
  const _SafetyCategory({required this.icon, required this.label, required this.emptyMessage, super.key});

  final IconData icon;
  final String label;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.mutedInk.withValues(alpha: 0.85)),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.eyebrow(size: 10)),
              const SizedBox(height: 2),
              Text(emptyMessage, style: theme.caption(size: 11.5)),
            ],
          ),
        ),
      ],
    );
  }
}
