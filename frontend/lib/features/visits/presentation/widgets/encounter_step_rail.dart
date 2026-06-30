import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Non-linear step navigation with completion badges (014 US4 / FR-014–016).
class EncounterStepRail extends StatelessWidget {
  const EncounterStepRail({
    required this.visitId,
    required this.activePhase,
    required this.badges,
    required this.onPhaseSelected,
    super.key,
  });

  final String visitId;
  final EncounterPhase activePhase;
  final PhaseBadges badges;
  final ValueChanged<EncounterPhase> onPhaseSelected;

  static const width = 208.0;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Semantics(
      label: 'Encounter steps',
      child: AppNotchedCard(
        key: const Key('encounter_step_rail'),
        titleIcon: Icons.linear_scale_rounded,
        title: Text('Steps', style: theme.title(size: 15)),
        description: Text('Jump to any phase', style: theme.caption(size: 11.5)),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(SpacingTokens.sm, 0, SpacingTokens.sm, SpacingTokens.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final phase in EncounterPhase.ordered) ...[
                _StepTile(
                  key: Key('encounter_step_${phase.name}'),
                  phase: phase,
                  badge: badges[phase] ?? PhaseCompletionBadge.empty,
                  isActive: activePhase == phase,
                  onTap: () => onPhaseSelected(phase),
                ),
                if (phase != EncounterPhase.review) const SizedBox(height: SpacingTokens.xs),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.phase, required this.badge, required this.isActive, required this.onTap, super.key});

  final EncounterPhase phase;
  final PhaseCompletionBadge badge;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final badgeVisual = _BadgeVisual.forBadge(badge, theme);

    return Material(
      color: isActive ? theme.pulse.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(theme.tileRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(theme.tileRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.sm + 2),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isActive ? theme.pulse.withValues(alpha: 0.14) : theme.tile,
                  borderRadius: BorderRadius.circular(theme.tileRadius - 2),
                  border: Border.all(color: isActive ? theme.pulse.withValues(alpha: 0.35) : theme.hairlineSoft),
                ),
                alignment: Alignment.center,
                child: Text(
                  phase.abbr,
                  style: theme.readout(color: isActive ? theme.pulseDeep : theme.mutedInk, size: 10),
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(child: Text(phase.label, style: theme.bodyStrong(size: 13))),
              Icon(badgeVisual.icon, size: 16, color: badgeVisual.color, semanticLabel: badgeVisual.semanticLabel),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeVisual {
  const _BadgeVisual({required this.icon, required this.color, required this.semanticLabel});

  final IconData icon;
  final Color color;
  final String semanticLabel;

  static _BadgeVisual forBadge(PhaseCompletionBadge badge, VisitTheme theme) => switch (badge) {
    PhaseCompletionBadge.empty => _BadgeVisual(
      icon: Icons.radio_button_unchecked,
      color: theme.mutedInk.withValues(alpha: 0.55),
      semanticLabel: 'Empty',
    ),
    PhaseCompletionBadge.hasContent => _BadgeVisual(
      icon: Icons.check_circle_outline,
      color: theme.pulseDeep,
      semanticLabel: 'Has content',
    ),
    PhaseCompletionBadge.error => _BadgeVisual(
      icon: Icons.error_outline,
      color: theme.danger,
      semanticLabel: 'Validation error',
    ),
  };
}
