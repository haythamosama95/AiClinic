import 'package:flutter/material.dart' hide Step;

import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/ui.dart';

const _steps = [
  Step(id: 'patient', label: 'Patient details', description: 'Demographics and contact'),
  Step(id: 'visit', label: 'Visit info', description: 'Reason and provider'),
  Step(id: 'billing', label: 'Billing', description: 'Services and payment'),
  Step(id: 'review', label: 'Review', description: 'Confirm and submit'),
];

class StepperShowcase extends StatefulWidget {
  const StepperShowcase({super.key});

  @override
  State<StepperShowcase> createState() => _StepperShowcaseState();
}

class _StepperShowcaseState extends State<StepperShowcase> {
  int _horizontal = 1;
  int _vertical = 0;

  @override
  Widget build(BuildContext context) {
    return ShowcaseSection(
      title: 'Stepper',
      description:
          'Multi-step flows with current, complete, and upcoming states.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.s4,
        children: [
          ShowcaseDemo(
            label: 'Horizontal',
            child: AppStepper(
              steps: _steps,
              currentStep: _horizontal,
              onBack: () => setState(
                () => _horizontal = (_horizontal - 1).clamp(0, _steps.length - 1),
              ),
              onNext: () => setState(
                () => _horizontal = (_horizontal + 1).clamp(0, _steps.length - 1),
              ),
            ),
          ),
          ShowcaseDemo(
            label: 'Vertical',
            child: SizedBox(
              width: 320,
              child: AppStepper(
                steps: _steps.sublist(0, 3),
                currentStep: _vertical,
                orientation: AppStepperOrientation.vertical,
                onBack: () => setState(() => _vertical = (_vertical - 1).clamp(0, 2)),
                onNext: () => setState(() => _vertical = (_vertical + 1).clamp(0, 2)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
