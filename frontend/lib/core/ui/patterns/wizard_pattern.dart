import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

import 'pattern_scaffold.dart';

/// Wizard page scaffold — numbered stepper with per-step validation.
///
/// Composes [AppStepper] (numbered) + per-step [stepContent] + back/next
/// with optional [onValidateStep] callbacks before advancing.
class WizardPattern extends StatefulWidget {
  const WizardPattern({
    required this.steps,
    required this.currentStep,
    required this.stepContent,
    this.onBack,
    this.onNext,
    this.onValidateStep,
    this.onFinish,
    this.onStepTap,
    this.backLabel = 'Back',
    this.nextLabel = 'Next',
    this.finishLabel = 'Finish',
    this.orientation = AppStepperOrientation.horizontal,
    super.key,
  });

  final List<AppStepperStep> steps;
  final int currentStep;
  final Widget stepContent;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final Future<bool> Function(int step)? onValidateStep;
  final VoidCallback? onFinish;
  final ValueChanged<int>? onStepTap;
  final String backLabel;
  final String nextLabel;
  final String finishLabel;
  final AppStepperOrientation orientation;

  @override
  State<WizardPattern> createState() => _WizardPatternState();
}

class _WizardPatternState extends State<WizardPattern> {
  bool get _isLastStep => widget.currentStep >= widget.steps.length - 1;

  Future<void> _handleNext() async {
    if (_isLastStep) {
      if (widget.onValidateStep != null) {
        final valid = await widget.onValidateStep!(widget.currentStep);
        if (!valid) return;
      }
      widget.onFinish?.call();
      return;
    }

    if (widget.onValidateStep != null) {
      final valid = await widget.onValidateStep!(widget.currentStep);
      if (!valid) return;
    }
    widget.onNext?.call();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = PatternScaffold.pagePadding(constraints.maxWidth);

        return Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppStepper(
                steps: widget.steps,
                currentStep: widget.currentStep,
                orientation: widget.orientation,
                onStepTap: widget.onStepTap,
                onBack: widget.onBack,
                onNext: (widget.onNext != null || widget.onFinish != null)
                    ? () => _handleNext()
                    : null,
                backLabel: widget.backLabel,
                nextLabel: _isLastStep ? widget.finishLabel : widget.nextLabel,
              ),
              const SizedBox(height: PatternScaffold.sectionGap),
              widget.stepContent,
            ],
          ),
        );
      },
    );
  }
}
