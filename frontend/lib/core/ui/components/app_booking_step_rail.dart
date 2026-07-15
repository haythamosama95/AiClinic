import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_stepper.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

const _bookingSteps = <AppStep>[
  AppStep(id: 'details', label: 'Details'),
  AppStep(id: 'schedule', label: 'Schedule'),
];

/// Horizontal step rail for multi-step booking dialogs (web `BookingStepRail`).
class AppBookingStepRail extends StatelessWidget {
  const AppBookingStepRail({required this.currentStep, super.key});

  final int currentStep;

  static const double _stepWidth = 96;
  static const double _indicatorSize = 32;
  static const double _connectorWidth = 72;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      label: 'Booking progress',
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int index = 0; index < _bookingSteps.length; index++) ...[
              _BookingStepColumn(
                step: _bookingSteps[index],
                index: index,
                currentStep: currentStep,
                colors: colors,
              ),
              if (index < _bookingSteps.length - 1)
                _BookingStepConnector(
                  completed: index < currentStep,
                  colors: colors,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BookingStepColumn extends StatelessWidget {
  const _BookingStepColumn({
    required this.step,
    required this.index,
    required this.currentStep,
    required this.colors,
  });

  final AppStep step;
  final int index;
  final int currentStep;
  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    final state = appStepStateFor(index, currentStep);

    return Semantics(
      selected: state == AppStepState.current,
      child: SizedBox(
        width: AppBookingStepRail._stepWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BookingStepIndicator(number: index + 1, state: state, colors: colors),
            const SizedBox(height: AppSpacing.space2),
            Text(
              step.label,
              textAlign: TextAlign.center,
              style: AppTypography.bodySm(context).copyWith(
                fontWeight: state == AppStepState.upcoming ? FontWeight.w400 : FontWeight.w500,
                color: state == AppStepState.upcoming ? colors.textTertiary : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingStepConnector extends StatelessWidget {
  const _BookingStepConnector({required this.completed, required this.colors});

  final bool completed;
  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
      child: SizedBox(
        width: AppBookingStepRail._connectorWidth,
        height: AppBookingStepRail._indicatorSize,
        child: Align(
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: AppMotion.resolveDuration(AppMotionPreset.fade),
            curve: AppMotion.resolveCurve(AppMotionPreset.fade),
            height: 1,
            color: completed ? colors.actionPrimary : colors.borderDefault,
          ),
        ),
      ),
    );
  }
}

class _BookingStepIndicator extends StatelessWidget {
  const _BookingStepIndicator({required this.number, required this.state, required this.colors});

  final int number;
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
        border: Border.all(color: focusBorder),
        boxShadow: [BoxShadow(color: focusBorder.withValues(alpha: 0.35), blurRadius: 0, spreadRadius: 3)],
      ),
      AppStepState.upcoming => BoxDecoration(
        color: colors.surfaceMuted,
        shape: BoxShape.circle,
        border: Border.all(color: colors.borderDefault),
      ),
    };

    final foreground = switch (state) {
      AppStepState.complete => colors.actionPrimaryFg,
      AppStepState.current => colors.textPrimary,
      AppStepState.upcoming => colors.textTertiary,
    };

    return AnimatedContainer(
      duration: AppMotion.resolveDuration(AppMotionPreset.fade),
      curve: AppMotion.resolveCurve(AppMotionPreset.fade),
      width: AppBookingStepRail._indicatorSize,
      height: AppBookingStepRail._indicatorSize,
      decoration: decoration,
      alignment: Alignment.center,
      child: state == AppStepState.complete
          ? Icon(Icons.check, size: 15, color: foreground)
          : Text(
              '$number',
              style: AppTypography.bodySm(context).copyWith(
                fontWeight: FontWeight.w500,
                color: foreground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
    );
  }
}
