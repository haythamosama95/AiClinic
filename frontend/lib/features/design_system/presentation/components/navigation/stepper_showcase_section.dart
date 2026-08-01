import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_stepper.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _StepperCopy {
  const _StepperCopy({
    required this.description,
    required this.horizontalLabel,
    required this.horizontalHint,
    required this.verticalLabel,
    required this.verticalHint,
    required this.back,
    required this.next,
    required this.patientLabel,
    required this.patientDescription,
    required this.visitLabel,
    required this.visitDescription,
    required this.billingLabel,
    required this.billingDescription,
    required this.reviewLabel,
    required this.reviewDescription,
  });

  final String description;
  final String horizontalLabel;
  final String horizontalHint;
  final String verticalLabel;
  final String verticalHint;
  final String back;
  final String next;
  final String patientLabel;
  final String patientDescription;
  final String visitLabel;
  final String visitDescription;
  final String billingLabel;
  final String billingDescription;
  final String reviewLabel;
  final String reviewDescription;
}

const _copyEn = _StepperCopy(
  description: 'Multi-step flows with current, complete, and upcoming states.',
  horizontalLabel: 'Horizontal',
  horizontalHint: 'orientation="horizontal"',
  verticalLabel: 'Vertical',
  verticalHint: 'orientation="vertical"',
  back: 'Back',
  next: 'Next',
  patientLabel: 'Patient details',
  patientDescription: 'Demographics and contact',
  visitLabel: 'Visit info',
  visitDescription: 'Reason and provider',
  billingLabel: 'Billing',
  billingDescription: 'Services and payment',
  reviewLabel: 'Review',
  reviewDescription: 'Confirm and submit',
);

const _copyAr = _StepperCopy(
  description: 'تدفقات متعددة الخطوات مع حالات الحالية والمكتملة والقادمة.',
  horizontalLabel: 'أفقي',
  horizontalHint: 'orientation="horizontal"',
  verticalLabel: 'عمودي',
  verticalHint: 'orientation="vertical"',
  back: 'رجوع',
  next: 'التالي',
  patientLabel: 'بيانات المريض',
  patientDescription: 'البيانات الديموغرافية والاتصال',
  visitLabel: 'معلومات الزيارة',
  visitDescription: 'السبب ومقدم الرعاية',
  billingLabel: 'الفوترة',
  billingDescription: 'الخدمات والدفع',
  reviewLabel: 'مراجعة',
  reviewDescription: 'تأكيد وإرسال',
);

_StepperCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

List<AppStep> _horizontalSteps(_StepperCopy copy) => [
  AppStep(id: 'patient', label: copy.patientLabel, description: copy.patientDescription),
  AppStep(id: 'visit', label: copy.visitLabel, description: copy.visitDescription),
  AppStep(id: 'billing', label: copy.billingLabel, description: copy.billingDescription),
  AppStep(id: 'review', label: copy.reviewLabel, description: copy.reviewDescription),
];

List<AppStep> _verticalSteps(_StepperCopy copy) => _horizontalSteps(copy).take(3).toList();

/// Stepper showcase (web `StepperShowcase`).
class StepperShowcaseSection extends ConsumerStatefulWidget {
  const StepperShowcaseSection({super.key});

  @override
  ConsumerState<StepperShowcaseSection> createState() => _StepperShowcaseSectionState();
}

class _StepperShowcaseSectionState extends ConsumerState<StepperShowcaseSection> {
  var _horizontalStep = 1;
  var _verticalStep = 0;

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final horizontalSteps = _horizontalSteps(copy);
    final verticalSteps = _verticalSteps(copy);

    return ShowcaseSection(
      id: 'stepper',
      title: 'Stepper',
      description: copy.description,
      componentName: 'Stepper',
      child: ShowcaseDemoGrid(
        columns: 1,
        children: [
          ShowcaseDemo(
            label: copy.horizontalLabel,
            propsHint: copy.horizontalHint,
            child: AppStepper(
              steps: horizontalSteps,
              currentStep: _horizontalStep,
              onStepChange: (step) => setState(() => _horizontalStep = step),
              backLabel: copy.back,
              nextLabel: copy.next,
            ),
          ),
          ShowcaseDemo(
            label: copy.verticalLabel,
            propsHint: copy.verticalHint,
            child: SizedBox(
              width: 384,
              child: AppStepper(
                steps: verticalSteps,
                currentStep: _verticalStep,
                orientation: AppStepperOrientation.vertical,
                onStepChange: (step) => setState(() => _verticalStep = step),
                backLabel: copy.back,
                nextLabel: copy.next,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
