import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_stepper.dart';

const _setupSteps = <AppStep>[
  AppStep(id: 'organization', label: 'Organization', description: 'Name & region'),
  AppStep(id: 'branch', label: 'Branch', description: 'Locations & hours'),
  AppStep(id: 'staff', label: 'Staff', description: 'Team & access'),
  AppStep(id: 'services', label: 'Services', description: 'Catalog & pricing'),
];

/// Vertical step rail for the setup wizard (web `VerticalStepRail`).
class SetupStepRail extends StatelessWidget {
  const SetupStepRail({required this.currentStep, super.key});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return AppStepper(
      orientation: AppStepperOrientation.vertical,
      steps: _setupSteps,
      currentStep: currentStep,
    );
  }
}
