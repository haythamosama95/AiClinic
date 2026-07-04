import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/actions/app_button.dart';

/// Progress state for one step in [AppStepper].
enum AppStepState {
  /// Step is finished — shows a check icon.
  complete,

  /// Active step — emphasized ring and label.
  current,

  /// Future step — muted styling.
  upcoming,
}

/// One step in an [AppStepper] sequence.
class AppStepperStep {
  const AppStepperStep({
    required this.id,
    required this.label,
    this.description,
  });

  final String id;
  final String label;
  final String? description;
}

/// Layout direction for [AppStepper].
enum AppStepperOrientation {
  horizontal,
  vertical,
}

/// Multi-step progress indicator with optional navigation actions.
class AppStepper extends StatelessWidget {
  const AppStepper({
    required this.steps,
    required this.currentStep,
    this.orientation = AppStepperOrientation.horizontal,
    this.onStepTap,
    this.onBack,
    this.onNext,
    this.backLabel = 'Back',
    this.nextLabel = 'Next',
    super.key,
  });

  final List<AppStepperStep> steps;
  final int currentStep;
  final AppStepperOrientation orientation;
  final ValueChanged<int>? onStepTap;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String backLabel;
  final String nextLabel;

  static AppStepState _stateForIndex(int index, int current) {
    if (index < current) return AppStepState.complete;
    if (index == current) return AppStepState.current;
    return AppStepState.upcoming;
  }

  @override
  Widget build(BuildContext context) {
    final isVertical = orientation == AppStepperOrientation.vertical;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Progress',
          container: true,
          child: isVertical
              ? _VerticalSteps(
                  steps: steps,
                  currentStep: currentStep,
                  onStepTap: onStepTap,
                )
              : _HorizontalSteps(
                  steps: steps,
                  currentStep: currentStep,
                  onStepTap: onStepTap,
                ),
        ),
        if (onBack != null || onNext != null) ...[
          const SizedBox(height: AppSpacing.s6),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: context.colors.borderSubtle),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: Row(
                children: [
                  if (onBack != null)
                    AppButton(
                      label: backLabel,
                      variant: AppButtonVariant.secondary,
                      onPressed: currentStep <= 0 ? null : onBack,
                    )
                  else
                    const Spacer(),
                  const Spacer(),
                  if (onNext != null)
                    AppButton(
                      label: nextLabel,
                      onPressed:
                          currentStep >= steps.length - 1 ? null : onNext,
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

class _HorizontalSteps extends StatelessWidget {
  const _HorizontalSteps({
    required this.steps,
    required this.currentStep,
    this.onStepTap,
  });

  final List<AppStepperStep> steps;
  final int currentStep;
  final ValueChanged<int>? onStepTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
            child: _HorizontalStepItem(
              step: steps[i],
              index: i,
              state: AppStepper._stateForIndex(i, currentStep),
              isLast: i == steps.length - 1,
              onTap: onStepTap == null ? null : () => onStepTap!(i),
            ),
          ),
      ],
    );
  }
}

class _HorizontalStepItem extends StatelessWidget {
  const _HorizontalStepItem({
    required this.step,
    required this.index,
    required this.state,
    required this.isLast,
    this.onTap,
  });

  final AppStepperStep step;
  final int index;
  final AppStepState state;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final labelColor = state == AppStepState.upcoming
        ? colors.textTertiary
        : colors.textPrimary;

    return Semantics(
      selected: state == AppStepState.current,
      child: Column(
        children: [
          Row(
            children: [
              _StepIndicator(
                number: index + 1,
                state: state,
                onTap: onTap,
              ),
              if (!isLast)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: AppSpacing.s2,
                      end: AppSpacing.s2,
                      top: AppSpacing.s4,
                    ),
                    child: _ConnectorLine(
                      color: state == AppStepState.complete
                          ? colors.actionPrimary
                          : colors.borderDefault,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
            child: Column(
              children: [
                Text(
                  step.label,
                  textAlign: TextAlign.center,
                  style: typography.bodyStrong.copyWith(color: labelColor),
                ),
                if (step.description != null) ...[
                  const SizedBox(height: AppSpacing.s0_5),
                  Text(
                    step.description!,
                    textAlign: TextAlign.center,
                    style: typography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalSteps extends StatelessWidget {
  const _VerticalSteps({
    required this.steps,
    required this.currentStep,
    this.onStepTap,
  });

  final List<AppStepperStep> steps;
  final int currentStep;
  final ValueChanged<int>? onStepTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          _VerticalStepItem(
            step: steps[i],
            index: i,
            state: AppStepper._stateForIndex(i, currentStep),
            isLast: i == steps.length - 1,
            onTap: onStepTap == null ? null : () => onStepTap!(i),
          ),
      ],
    );
  }
}

class _VerticalStepItem extends StatelessWidget {
  const _VerticalStepItem({
    required this.step,
    required this.index,
    required this.state,
    required this.isLast,
    this.onTap,
  });

  final AppStepperStep step;
  final int index;
  final AppStepState state;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final labelColor = state == AppStepState.upcoming
        ? colors.textTertiary
        : colors.textPrimary;

    return Semantics(
      selected: state == AppStepState.current,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: AppSpacing.s8,
              child: Column(
                children: [
                  _StepIndicator(
                    number: index + 1,
                    state: state,
                    onTap: onTap,
                  ),
                  if (!isLast)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.s1,
                        ),
                        child: _ConnectorLine(
                          vertical: true,
                          color: state == AppStepState.complete
                              ? colors.actionPrimary
                              : colors.borderDefault,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: isLast ? 0 : AppSpacing.s6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.label,
                      style: typography.bodyStrong.copyWith(color: labelColor),
                    ),
                    if (step.description != null) ...[
                      const SizedBox(height: AppSpacing.s0_5),
                      Text(
                        step.description!,
                        style: typography.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.number,
    required this.state,
    this.onTap,
  });

  final int number;
  final AppStepState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    final decoration = switch (state) {
      AppStepState.complete => BoxDecoration(
        shape: BoxShape.circle,
        color: colors.actionPrimary,
        border: Border.all(color: colors.actionPrimary),
      ),
      AppStepState.current => BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surfaceDefault,
        border: Border.all(color: colors.borderFocus, width: AppSpacing.sPx),
        boxShadow: [
          BoxShadow(
            color: colors.focusRing,
            spreadRadius: AppSpacing.sPx,
          ),
        ],
      ),
      AppStepState.upcoming => BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surfaceDefault,
        border: Border.all(color: colors.borderDefault),
      ),
    };

    final child = SizedBox(
      width: AppSpacing.s8,
      height: AppSpacing.s8,
      child: DecoratedBox(
        decoration: decoration,
        child: Center(
          child: state == AppStepState.complete
              ? AppIcon(
                  icon: LucideIcons.check,
                  dimension: AppIconSize.sm.value,
                  color: colors.actionPrimaryFg,
                )
              : Text(
                  _formatWesternInt(number),
                  style: typography.bodySm.copyWith(
                    fontWeight: FontWeight.w500,
                    color: state == AppStepState.upcoming
                        ? colors.textTertiary
                        : colors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
        ),
      ),
    );

    if (onTap == null) return child;

    return AppPressable(
      onTap: onTap,
      semanticLabel: 'Step $number',
      borderRadius: AppRadii.fullAll,
      child: child,
    );
  }
}

class _ConnectorLine extends StatelessWidget {
  const _ConnectorLine({
    required this.color,
    this.vertical = false,
  });

  final Color color;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: SizedBox(
        width: vertical ? AppSpacing.sPx : double.infinity,
        height: vertical ? double.infinity : AppSpacing.sPx,
      ),
    );
  }
}

String _formatWesternInt(int value) {
  const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  var text = value.toString();
  for (var i = 0; i < 10; i++) {
    text = text.replaceAll(eastern[i], '$i').replaceAll(persian[i], '$i');
  }
  return text;
}
