import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// A single step in [AppStepper].
class AppStep {
  const AppStep({required this.id, required this.label, this.description});

  final String id;
  final String label;
  final String? description;
}

enum AppStepperOrientation { horizontal, vertical }

enum AppStepState { complete, current, upcoming }

AppStepState appStepStateFor(int index, int currentStep) {
  if (index < currentStep) return AppStepState.complete;
  if (index == currentStep) return AppStepState.current;
  return AppStepState.upcoming;
}

/// Multi-step progress indicator with optional Back/Next navigation.
class AppStepper extends StatelessWidget {
  const AppStepper({
    required this.steps,
    required this.currentStep,
    this.onStepChange,
    this.orientation = AppStepperOrientation.horizontal,
    this.backLabel = 'Back',
    this.nextLabel = 'Next',
    super.key,
  });

  final List<AppStep> steps;
  final int currentStep;
  final ValueChanged<int>? onStepChange;
  final AppStepperOrientation orientation;
  final String backLabel;
  final String nextLabel;

  static const double _indicatorSize = 32;
  static const double _connectorThickness = 1;

  bool get _isVertical => orientation == AppStepperOrientation.vertical;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'Progress',
          child: _isVertical
              ? _VerticalStepList(steps: steps, currentStep: currentStep, colors: colors)
              : _HorizontalStepList(steps: steps, currentStep: currentStep, colors: colors),
        ),
        if (onStepChange != null) ...[
          const SizedBox(height: AppSpacing.space6),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.borderSubtle)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.space4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    disabled: currentStep <= 0,
                    onPressed: currentStep <= 0 ? null : () => onStepChange!(currentStep - 1),
                    child: Text(backLabel),
                  ),
                  AppButton(
                    disabled: currentStep >= steps.length - 1,
                    onPressed: currentStep >= steps.length - 1 ? null : () => onStepChange!(currentStep + 1),
                    child: Text(nextLabel),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HorizontalStepList extends StatelessWidget {
  const _HorizontalStepList({required this.steps, required this.currentStep, required this.colors});

  final List<AppStep> steps;
  final int currentStep;
  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int index = 0; index < steps.length; index++) ...[
          Expanded(
            child: _HorizontalStepItem(
              step: steps[index],
              index: index,
              currentStep: currentStep,
              isLast: index == steps.length - 1,
              colors: colors,
            ),
          ),
        ],
      ],
    );
  }
}

class _HorizontalStepItem extends StatelessWidget {
  const _HorizontalStepItem({
    required this.step,
    required this.index,
    required this.currentStep,
    required this.isLast,
    required this.colors,
  });

  final AppStep step;
  final int index;
  final int currentStep;
  final bool isLast;
  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    final state = appStepStateFor(index, currentStep);

    return Semantics(
      selected: state == AppStepState.current,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              _StepIndicator(number: index + 1, state: state, colors: colors),
              if (!isLast)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
                    child: _StepConnector(orientation: AppStepperOrientation.horizontal, state: state, colors: colors),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
            child: _StepLabels(step: step, state: state, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

class _VerticalStepList extends StatelessWidget {
  const _VerticalStepList({required this.steps, required this.currentStep, required this.colors});

  final List<AppStep> steps;
  final int currentStep;
  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int index = 0; index < steps.length; index++)
          _VerticalStepItem(
            step: steps[index],
            index: index,
            currentStep: currentStep,
            isLast: index == steps.length - 1,
            colors: colors,
          ),
      ],
    );
  }
}

class _VerticalStepItem extends StatelessWidget {
  const _VerticalStepItem({
    required this.step,
    required this.index,
    required this.currentStep,
    required this.isLast,
    required this.colors,
  });

  final AppStep step;
  final int index;
  final int currentStep;
  final bool isLast;
  final AppSemanticColors colors;

  static const double _indicatorSize = AppStepper._indicatorSize;
  static const double _connectorThickness = AppStepper._connectorThickness;
  static const double _stepGap = AppSpacing.space8;
  static const double _lineStart = (_indicatorSize - _connectorThickness) / 2;

  @override
  Widget build(BuildContext context) {
    final state = appStepStateFor(index, currentStep);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : _stepGap),
      child: Semantics(
        selected: state == AppStepState.current,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _indicatorSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (!isLast)
                    PositionedDirectional(
                      start: _lineStart,
                      top: _indicatorSize,
                      bottom: -_stepGap,
                      width: _connectorThickness,
                      child: _StepConnector(orientation: AppStepperOrientation.vertical, state: state, colors: colors),
                    ),
                  _StepIndicator(number: index + 1, state: state, colors: colors),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: _StepLabels(step: step, state: state, textAlign: TextAlign.start),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepLabels extends StatelessWidget {
  const _StepLabels({required this.step, required this.state, required this.textAlign});

  final AppStep step;
  final AppStepState state;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: textAlign == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          step.label,
          textAlign: textAlign,
          style: AppTypography.bodyStrong(
            context,
          ).copyWith(color: state == AppStepState.upcoming ? colors.textTertiary : colors.textPrimary),
        ),
        if (step.description != null) ...[
          const SizedBox(height: 2),
          Text(
            step.description!,
            textAlign: textAlign,
            style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.number, required this.state, required this.colors});

  final int number;
  final AppStepState state;
  final AppSemanticColors colors;

  static const double _size = AppStepper._indicatorSize;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final focusBorder = brightness == Brightness.dark ? AppColorPrimitives.teal400 : AppColorPrimitives.teal500;
    final focusRing = appInputFocusRingColor(context);

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
        boxShadow: [BoxShadow(color: focusRing, blurRadius: 0, spreadRadius: 2)],
      ),
      AppStepState.upcoming => BoxDecoration(
        color: colors.surfaceDefault,
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
      width: _size,
      height: _size,
      decoration: decoration,
      alignment: Alignment.center,
      child: state == AppStepState.complete
          ? Icon(Icons.check, size: 16, color: foreground)
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

class _StepConnector extends StatelessWidget {
  const _StepConnector({required this.orientation, required this.state, required this.colors});

  final AppStepperOrientation orientation;
  final AppStepState state;
  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    final color = state == AppStepState.complete ? colors.actionPrimary : colors.borderDefault;

    return AnimatedContainer(
      duration: AppMotion.resolveDuration(AppMotionPreset.fade),
      curve: AppMotion.resolveCurve(AppMotionPreset.fade),
      height: orientation == AppStepperOrientation.horizontal ? AppStepper._connectorThickness : null,
      width: orientation == AppStepperOrientation.vertical ? AppStepper._connectorThickness : null,
      margin: orientation == AppStepperOrientation.horizontal
          ? const EdgeInsets.only(top: AppStepper._indicatorSize / 2)
          : null,
      color: color,
    );
  }
}
