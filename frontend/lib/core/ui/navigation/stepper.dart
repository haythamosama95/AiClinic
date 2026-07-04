import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/actions/button.dart';

enum StepState { complete, current, upcoming }

/// Single step in [AppStepper].
@immutable
class Step {
  const Step({
    required this.id,
    required this.label,
    this.description,
  });

  final String id;
  final String label;
  final String? description;
}

enum AppStepperOrientation { horizontal, vertical }

/// Multi-step progress indicator with optional back/next actions.
class AppStepper extends StatelessWidget {
  const AppStepper({
    super.key,
    required this.steps,
    required this.currentStep,
    this.orientation = AppStepperOrientation.horizontal,
    this.onBack,
    this.onNext,
    this.backLabel = 'Back',
    this.nextLabel = 'Next',
  });

  final List<Step> steps;
  final int currentStep;
  final AppStepperOrientation orientation;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String backLabel;
  final String nextLabel;

  StepState _stepState(int index) {
    if (index < currentStep) return StepState.complete;
    if (index == currentStep) return StepState.current;
    return StepState.upcoming;
  }

  @override
  Widget build(BuildContext context) {
    final isVertical = orientation == AppStepperOrientation.vertical;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          container: true,
          label: 'Progress',
          child: isVertical
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < steps.length; index++)
                      _VerticalStep(
                        step: steps[index],
                        number: index,
                        state: _stepState(index),
                        isLast: index == steps.length - 1,
                      ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < steps.length; index++)
                      Expanded(
                        child: _HorizontalStep(
                          step: steps[index],
                          number: index,
                          state: _stepState(index),
                          isLast: index == steps.length - 1,
                        ),
                      ),
                  ],
                ),
        ),
        if (onBack != null || onNext != null) ...[
          const SizedBox(height: AppSpacing.s6),
          Divider(height: 1, color: context.colors.borderSubtle),
          const SizedBox(height: AppSpacing.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              onBack != null
                  ? AppButton(
                      variant: AppButtonVariant.secondary,
                      onPressed: currentStep <= 0 ? null : onBack,
                      child: Text(backLabel),
                    )
                  : const SizedBox.shrink(),
              if (onNext != null)
                AppButton(
                  onPressed: currentStep >= steps.length - 1 ? null : onNext,
                  child: Text(nextLabel),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _HorizontalStep extends StatelessWidget {
  const _HorizontalStep({
    required this.step,
    required this.number,
    required this.state,
    required this.isLast,
  });

  final Step step;
  final int number;
  final StepState state;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: state == StepState.current ? 'Current step' : step.label,
      child: Column(
        children: [
          Row(
            children: [
              _StepIndicator(number: number, state: state),
              if (!isLast)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
                    child: _Connector(
                      horizontal: true,
                      complete: state == StepState.complete,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
            child: _StepLabels(step: step, state: state, centered: true),
          ),
        ],
      ),
    );
  }

}

class _VerticalStep extends StatelessWidget {
  const _VerticalStep({
    required this.step,
    required this.number,
    required this.state,
    required this.isLast,
  });

  final Step step;
  final int number;
  final StepState state;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: state == StepState.current ? 'Current step' : step.label,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                _StepIndicator(number: number, state: state),
                if (!isLast)
                  Expanded(
                    child: _Connector(
                      horizontal: false,
                      complete: state == StepState.complete,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.s6),
                child: _StepLabels(step: step, state: state),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepLabels extends StatelessWidget {
  const _StepLabels({
    required this.step,
    required this.state,
    this.centered = false,
  });

  final Step step;
  final StepState state;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          step.label,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: typography.bodyStrong.copyWith(
            color: state == StepState.upcoming
                ? colors.textTertiary
                : colors.textPrimary,
          ),
        ),
        if (step.description != null) ...[
          const SizedBox(height: AppSpacing.s0_5),
          Text(
            step.description!,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: typography.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.number,
    required this.state,
  });

  final int number;
  final StepState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final decoration = switch (state) {
      StepState.complete => BoxDecoration(
        color: colors.actionPrimary,
        border: Border.all(color: colors.actionPrimary),
      ),
      StepState.current => BoxDecoration(
        color: colors.surfaceDefault,
        border: Border.all(color: colors.borderFocus, width: 2),
        boxShadow: [
          BoxShadow(
            color: colors.focusRing.withValues(alpha: 0.5),
            blurRadius: 0,
            spreadRadius: 2,
          ),
        ],
      ),
      StepState.upcoming => BoxDecoration(
        color: colors.surfaceDefault,
        border: Border.all(color: colors.borderDefault),
      ),
    };

    final textStyle = context.typography.bodySm.copyWith(
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: state == StepState.complete
          ? colors.actionPrimaryFg
          : state == StepState.current
          ? colors.textPrimary
          : colors.textTertiary,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: decoration.color,
        border: decoration.border,
        boxShadow: decoration.boxShadow,
      ),
      child: SizedBox(
        width: 32,
        height: 32,
        child: Center(
          child: state == StepState.complete
              ? Icon(Icons.check, size: 16, color: colors.actionPrimaryFg)
              : Text('${number + 1}', style: textStyle),
        ),
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({
    required this.horizontal,
    required this.complete,
  });

  final bool horizontal;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final color = complete
        ? context.colors.actionPrimary
        : context.colors.borderDefault;

    if (horizontal) {
      return Container(
        height: 1,
        margin: const EdgeInsets.only(top: 16),
        color: color,
      );
    }

    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.s0_5),
      color: color,
    );
  }
}
