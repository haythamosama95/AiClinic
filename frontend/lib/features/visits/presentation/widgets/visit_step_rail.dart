import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';

/// Three-step encounter progress rail (web `VisitStepRail`).
class VisitStepRail extends ConsumerWidget {
  const VisitStepRail({
    required this.visitId,
    this.onPhaseSelect,
    super.key,
  });

  final String visitId;
  final ValueChanged<EncounterPhase>? onPhaseSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(encounterPhaseBadgesProvider(visitId));
    final activePhase = ref.watch(encounterActivePhaseProvider(visitId));
    final phases = EncounterPhase.stepperPhases;
    final currentIndex = activePhase.stepperIndex;

    return Semantics(
      label: 'Visit progress',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < phases.length; index++)
            Expanded(
              child: _StepNode(
                phase: phases[index],
                index: index,
                activePhase: activePhase,
                currentIndex: currentIndex,
                badge: badges[phases[index]] ?? PhaseCompletionBadge.empty,
                connectorComplete: index < phases.length - 1
                    ? _connectorComplete(index, currentIndex, activePhase)
                    : null,
                onPhaseSelect: onPhaseSelect,
              ),
            ),
        ],
      ),
    );
  }

  static bool _connectorComplete(int index, int currentIndex, EncounterPhase activePhase) {
    if (activePhase == EncounterPhase.review) {
      return true;
    }
    return index < currentIndex;
  }
}

AppStepState _stepStateForPhase({
  required EncounterPhase phase,
  required EncounterPhase activePhase,
  required int currentIndex,
  required PhaseCompletionBadge badge,
}) {
  if (activePhase == EncounterPhase.review) {
    return AppStepState.complete;
  }

  final phaseIndex = phase.stepperIndex;

  if (phaseIndex == currentIndex) {
    return AppStepState.current;
  }

  if (phaseIndex < currentIndex) {
    return AppStepState.complete;
  }

  return switch (badge) {
    PhaseCompletionBadge.empty => AppStepState.upcoming,
    PhaseCompletionBadge.hasContent || PhaseCompletionBadge.error => AppStepState.complete,
  };
}

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.phase,
    required this.index,
    required this.activePhase,
    required this.currentIndex,
    required this.badge,
    required this.connectorComplete,
    this.onPhaseSelect,
  });

  final EncounterPhase phase;
  final int index;
  final EncounterPhase activePhase;
  final int currentIndex;
  final PhaseCompletionBadge badge;
  final bool? connectorComplete;
  final ValueChanged<EncounterPhase>? onPhaseSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = _stepStateForPhase(
      phase: phase,
      activePhase: activePhase,
      currentIndex: currentIndex,
      badge: badge,
    );
    final clickable = onPhaseSelect != null && state != AppStepState.upcoming && activePhase != EncounterPhase.review;
    final indicatorSize = MediaQuery.sizeOf(context).width >= 640 ? 28.0 : 24.0;
    final label = phase.label;
    final shortLabel = phase == EncounterPhase.objective ? 'Findings' : label;
    final showShortLabel = MediaQuery.sizeOf(context).width < 640;

    return Semantics(
      button: clickable,
      enabled: clickable,
      selected: state == AppStepState.current,
      label: '$label${state == AppStepState.complete
          ? ' (completed)'
          : state == AppStepState.current
          ? ' (current)'
          : ''}',
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          if (connectorComplete != null)
            PositionedDirectional(
              start: indicatorSize / 2 + AppSpacing.space3,
              top: indicatorSize / 2,
              end: -(indicatorSize / 2 + AppSpacing.space3),
              child: _ConnectorLine(complete: connectorComplete!),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: clickable ? () => onPhaseSelect!(phase) : null,
                  customBorder: const CircleBorder(),
                  child: _StepCircle(state: state, icon: phase.icon, colors: colors, size: indicatorSize),
                ),
              ),
              const SizedBox(height: AppSpacing.space1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space1),
                child: Text(
                  showShortLabel ? shortLabel : label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption(context).copyWith(
                    color: switch (state) {
                      AppStepState.current => AppColorPrimitives.teal700,
                      AppStepState.upcoming => colors.textTertiary,
                      AppStepState.complete => colors.textSecondary,
                    },
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectorLine extends StatefulWidget {
  const _ConnectorLine({required this.complete});

  final bool complete;

  @override
  State<_ConnectorLine> createState() => _ConnectorLineState();
}

class _ConnectorLineState extends State<_ConnectorLine> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.quick, value: widget.complete ? 1 : 0);
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: AppMotionEasing.out),
    );
  }

  @override
  void didUpdateWidget(covariant _ConnectorLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.complete == widget.complete) {
      return;
    }
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    if (reducedMotion) {
      _controller.value = widget.complete ? 1 : 0;
      return;
    }
    _controller.animateTo(widget.complete ? 1 : 0, duration: AppMotion.quick, curve: AppMotionEasing.out);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SizedBox(
      height: 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: colors.borderDefault),
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: _animation.value.clamp(0, 1),
                child: ColoredBox(color: colors.actionPrimary),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StepCircle extends StatelessWidget {
  const _StepCircle({
    required this.state,
    required this.icon,
    required this.colors,
    required this.size,
  });

  final AppStepState state;
  final IconData icon;
  final AppSemanticColors colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final focusBorder = brightness == Brightness.dark ? AppColorPrimitives.teal400 : AppColorPrimitives.teal500;

    final decoration = switch (state) {
      AppStepState.complete => BoxDecoration(
        color: colors.actionPrimary,
        shape: BoxShape.circle,
        border: Border.all(color: colors.actionPrimary),
      ),
      AppStepState.current => BoxDecoration(
        color: colors.surfaceRaised,
        shape: BoxShape.circle,
        border: Border.all(color: focusBorder),
        boxShadow: [
          BoxShadow(color: colors.surfaceRaised, blurRadius: 0, spreadRadius: 2),
          BoxShadow(color: focusBorder.withValues(alpha: 0.15), blurRadius: 0, spreadRadius: 4),
        ],
      ),
      AppStepState.upcoming => BoxDecoration(
        color: colors.surfaceDefault,
        shape: BoxShape.circle,
        border: Border.all(color: colors.borderDefault),
      ),
    };

    final iconColor = switch (state) {
      AppStepState.complete => colors.actionPrimaryFg,
      AppStepState.current => AppColorPrimitives.teal600,
      AppStepState.upcoming => colors.textTertiary,
    };

    return Container(
      width: size,
      height: size,
      decoration: decoration,
      alignment: Alignment.center,
      child: Icon(
        state == AppStepState.complete ? Icons.check_rounded : icon,
        size: 12,
        color: iconColor,
      ),
    );
  }
}
