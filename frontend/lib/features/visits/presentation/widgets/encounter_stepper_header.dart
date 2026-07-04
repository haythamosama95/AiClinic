import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';

/// Horizontal encounter-phase stepper with completion badges (014 US4).
class EncounterStepperHeader extends StatelessWidget {
  const EncounterStepperHeader({
    required this.activePhase,
    required this.badges,
    required this.onPhaseSelected,
    super.key,
  });

  final EncounterPhase activePhase;
  final PhaseBadges badges;
  final ValueChanged<EncounterPhase> onPhaseSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final phases = EncounterPhase.stepperPhases;
    final activeIndex = activePhase.stepperIndex;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < phases.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.s2),
                child: SizedBox(
                  width: AppSpacing.s6,
                  child: ColoredBox(
                    color: i <= activeIndex ? colors.actionPrimary : colors.borderDefault,
                    child: const SizedBox(height: AppSpacing.sPx * 2),
                  ),
                ),
              ),
            _PhasePill(
              phase: phases[i],
              isActive: i == activeIndex,
              isComplete: i < activeIndex,
              badge: badges[phases[i]] ?? PhaseCompletionBadge.empty,
              onTap: () => onPhaseSelected(phases[i]),
              typography: typography,
              colors: colors,
            ),
          ],
        ],
      ),
    );
  }
}

class _PhasePill extends StatelessWidget {
  const _PhasePill({
    required this.phase,
    required this.isActive,
    required this.isComplete,
    required this.badge,
    required this.onTap,
    required this.typography,
    required this.colors,
  });

  final EncounterPhase phase;
  final bool isActive;
  final bool isComplete;
  final PhaseCompletionBadge badge;
  final VoidCallback onTap;
  final AppTypography typography;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final highlighted = isActive || isComplete;
    final background = highlighted ? colors.actionPrimary : colors.surfaceSunken;
    final foreground = highlighted ? colors.actionPrimaryFg : colors.textSecondary;

    return AppPressable(
      onTap: onTap,
      borderRadius: AppRadii.fullAll,
      semanticLabel: phase.label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadii.fullAll,
          border: Border.all(
            color: highlighted ? colors.actionPrimary : colors.borderDefault,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: colors.focusRing,
                    blurRadius: AppSpacing.s2,
                    spreadRadius: AppSpacing.sPx,
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.s3,
            vertical: AppSpacing.s2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                icon: isComplete ? LucideIcons.check : _phaseIcon(phase),
                size: AppIconSize.sm,
                color: foreground,
              ),
              const SizedBox(width: AppSpacing.s2),
              Text(
                phase.label,
                style: typography.bodyStrong.copyWith(color: foreground),
              ),
              if (badge != PhaseCompletionBadge.empty) ...[
                const SizedBox(width: AppSpacing.s1),
                _BadgeIcon(badge: badge, onPrimary: highlighted),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _phaseIcon(EncounterPhase phase) => switch (phase) {
    EncounterPhase.subjective => LucideIcons.messageSquare,
    EncounterPhase.objective => LucideIcons.stethoscope,
    EncounterPhase.plan => LucideIcons.pill,
    _ => LucideIcons.fileText,
  };
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({required this.badge, required this.onPrimary});

  final PhaseCompletionBadge badge;
  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return switch (badge) {
      PhaseCompletionBadge.hasContent => AppIcon(
        icon: LucideIcons.checkCircle2,
        size: AppIconSize.sm,
        color: onPrimary ? colors.actionPrimaryFg : colors.statusSuccessFg,
        semanticLabel: 'Has content',
      ),
      PhaseCompletionBadge.error => AppIcon(
        icon: LucideIcons.alertCircle,
        size: AppIconSize.sm,
        color: onPrimary ? colors.actionPrimaryFg : colors.statusDangerFg,
        semanticLabel: 'Validation error',
      ),
      PhaseCompletionBadge.empty => const SizedBox.shrink(),
    };
  }
}
