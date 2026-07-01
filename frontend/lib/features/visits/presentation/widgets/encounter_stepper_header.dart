import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Horizontal encounter-phase stepper header owned by the visit workspace (014).
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

  static const _connectorThickness = 2.5;
  static const _connectorAnimationDuration = Duration(milliseconds: 350);

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final shape = context.shapeTokens;
    final theme = Theme.of(context);
    final visitTheme = context.visitTheme;
    final phases = EncounterPhase.ordered;
    final activeIndex = activePhase.orderIndex;

    final titleStyle = theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    final pillRadius = shape.md + 2;
    final connectorWidth = 3 * SpacingTokens.xxl;

    return KeyedSubtree(
      key: const Key('encounter_stepper'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < phases.length; i++) ...[
            if (i > 0)
              SizedBox(
                width: connectorWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.xs),
                  child: _StepConnector(
                    filled: i <= activeIndex,
                    activeColor: colors.primary,
                    inactiveColor: colors.border,
                    thickness: _connectorThickness,
                    animationDuration: _connectorAnimationDuration,
                  ),
                ),
              ),
            Flexible(
              fit: FlexFit.loose,
              child: _StepPill(
                key: Key('encounter_step_${phases[i].name}'),
                phase: phases[i],
                state: _stepState(i, activeIndex),
                badge: badges[phases[i]] ?? PhaseCompletionBadge.empty,
                visitTheme: visitTheme,
                pillRadius: pillRadius,
                titleStyle: titleStyle,
                onTap: () => onPhaseSelected(phases[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static _StepVisualState _stepState(int index, int activeIndex) {
    if (index < activeIndex) {
      return _StepVisualState.completed;
    }
    if (index == activeIndex) {
      return _StepVisualState.active;
    }
    return _StepVisualState.inactive;
  }
}

enum _StepVisualState { completed, active, inactive }

class _StepConnector extends StatelessWidget {
  const _StepConnector({
    required this.filled,
    required this.activeColor,
    required this.inactiveColor,
    required this.thickness,
    required this.animationDuration,
  });

  final bool filled;
  final Color activeColor;
  final Color inactiveColor;
  final double thickness;
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: thickness,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: filled ? 1 : 0),
        duration: animationDuration,
        curve: Curves.easeInOut,
        builder: (context, progress, _) {
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: inactiveColor),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress.clamp(0, 1),
                    heightFactor: 1,
                    child: ColoredBox(color: activeColor),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill({
    super.key,
    required this.phase,
    required this.state,
    required this.badge,
    required this.visitTheme,
    required this.pillRadius,
    required this.titleStyle,
    required this.onTap,
  });

  final EncounterPhase phase;
  final _StepVisualState state;
  final PhaseCompletionBadge badge;
  final VisitTheme visitTheme;
  final double pillRadius;
  final TextStyle? titleStyle;
  final VoidCallback onTap;

  static const _iconSize = 18.0;
  static const _borderWidth = 1.0;
  static const _pillHeight = SpacingTokens.sm * 2 + _iconSize + _borderWidth * 2;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final isHighlighted = state != _StepVisualState.inactive;
    final foreground = isHighlighted ? colors.primaryForeground : colors.mutedForeground;
    final stepIcon = state == _StepVisualState.completed ? Icons.check_rounded : phase.icon;

    return Semantics(
      button: true,
      selected: state == _StepVisualState.active,
      label: phase.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _pillHeight,
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
            decoration: BoxDecoration(
              color: isHighlighted ? colors.primary : colors.muted,
              borderRadius: BorderRadius.circular(pillRadius),
              border: Border.all(color: isHighlighted ? Colors.transparent : colors.border, width: _borderWidth),
              boxShadow: state == _StepVisualState.active
                  ? [BoxShadow(color: colors.primary.withValues(alpha: 0.35), blurRadius: 8, spreadRadius: 2)]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: _iconSize,
                  height: _iconSize,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                    child: Icon(stepIcon, key: ValueKey(stepIcon), size: _iconSize, color: foreground),
                  ),
                ),
                const SizedBox(width: SpacingTokens.sm),
                Flexible(
                  child: Text(
                    phase.label,
                    style: titleStyle?.copyWith(color: foreground),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_badgeIcon(badge, isHighlighted) case final icon?) ...[
                  const SizedBox(width: SpacingTokens.xs),
                  icon,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget? _badgeIcon(PhaseCompletionBadge badge, bool onPrimary) {
    const size = 16.0;
    return switch (badge) {
      PhaseCompletionBadge.empty => null,
      PhaseCompletionBadge.hasContent => Icon(
        Icons.check_circle_outline,
        size: size,
        color: onPrimary ? Colors.white.withValues(alpha: 0.9) : visitTheme.pulseDeep,
        semanticLabel: 'Has content',
      ),
      PhaseCompletionBadge.error => Icon(
        Icons.error_outline,
        size: size,
        color: onPrimary ? Colors.white : visitTheme.danger,
        semanticLabel: 'Validation error',
      ),
    };
  }
}
