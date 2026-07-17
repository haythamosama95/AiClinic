import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_stepper.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';

/// Horizontal icon step rail for the visit encounter header.
class VisitEncounterStepRail extends StatelessWidget {
  const VisitEncounterStepRail({required this.currentPhase, this.onPhaseSelected, super.key});

  final EncounterPhase currentPhase;
  final ValueChanged<EncounterPhase>? onPhaseSelected;

  static const double indicatorSize = 32;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final phases = EncounterPhase.stepperPhases;
    final currentStep = currentPhase.stepperIndex.clamp(0, phases.length - 1);

    return Semantics(
      label: 'Visit progress',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int index = 0; index < phases.length; index++)
            Expanded(
              child: _EncounterStepItem(
                phase: phases[index],
                index: index,
                stepCount: phases.length,
                currentStep: currentStep,
                colors: colors,
                onTap: onPhaseSelected,
              ),
            ),
        ],
      ),
    );
  }
}

class _EncounterStepItem extends StatelessWidget {
  const _EncounterStepItem({
    required this.phase,
    required this.index,
    required this.stepCount,
    required this.currentStep,
    required this.colors,
    this.onTap,
  });

  final EncounterPhase phase;
  final int index;
  final int stepCount;
  final int currentStep;
  final AppSemanticColors colors;
  final ValueChanged<EncounterPhase>? onTap;

  @override
  Widget build(BuildContext context) {
    final state = appStepStateFor(index, currentStep);
    final labelColor = switch (state) {
      AppStepState.current => colors.actionPrimary,
      AppStepState.complete => colors.textPrimary,
      AppStepState.upcoming => colors.textTertiary,
    };

    final indicator = _EncounterStepIndicator(icon: phase.icon, state: state, colors: colors);

    final stepIcon = onTap == null
        ? indicator
        : Semantics(
            button: true,
            selected: state == AppStepState.current,
            label: phase.label,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(onTap: () => onTap!(phase), customBorder: const CircleBorder(), child: indicator),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: index > 0
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: _EncounterStepConnector(completed: index - 1 < currentStep, colors: colors),
                    )
                  : const SizedBox.shrink(),
            ),
            stepIcon,
            Expanded(
              child: index < stepCount - 1
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: _EncounterStepConnector(completed: index < currentStep, colors: colors),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space05),
          child: Text(
            phase.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption(context).copyWith(
              fontWeight: state == AppStepState.current ? FontWeight.w600 : FontWeight.w500,
              color: labelColor,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _EncounterStepConnector extends StatelessWidget {
  const _EncounterStepConnector({required this.completed, required this.colors});

  final bool completed;
  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.resolveDuration(AppMotionPreset.fade),
      curve: AppMotion.resolveCurve(AppMotionPreset.fade),
      height: 1,
      width: double.infinity,
      color: completed ? colors.actionPrimary : colors.borderDefault,
    );
  }
}

class _EncounterStepIndicator extends StatelessWidget {
  const _EncounterStepIndicator({required this.icon, required this.state, required this.colors});

  final IconData icon;
  final AppStepState state;
  final AppSemanticColors colors;

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
        color: colors.surfaceDefault,
        shape: BoxShape.circle,
        border: Border.all(color: focusBorder, width: 1.5),
      ),
      AppStepState.upcoming => BoxDecoration(
        color: colors.surfaceDefault,
        shape: BoxShape.circle,
        border: Border.all(color: colors.borderDefault),
      ),
    };

    final foreground = switch (state) {
      AppStepState.complete => colors.actionPrimaryFg,
      AppStepState.current => focusBorder,
      AppStepState.upcoming => colors.textTertiary,
    };

    return AnimatedContainer(
      duration: AppMotion.resolveDuration(AppMotionPreset.fade),
      curve: AppMotion.resolveCurve(AppMotionPreset.fade),
      width: VisitEncounterStepRail.indicatorSize,
      height: VisitEncounterStepRail.indicatorSize,
      decoration: decoration,
      alignment: Alignment.center,
      child: state == AppStepState.complete
          ? Icon(Icons.check, size: 14, color: foreground)
          : Icon(icon, size: 16, color: foreground),
    );
  }
}
