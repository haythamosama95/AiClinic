import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_progress.dart';
import 'package:ai_clinic/core/ui/components/app_slider.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _ProgressCopy {
  const _ProgressCopy({
    required this.description,
    required this.barDeterminateLabel,
    required this.barDeterminateHint,
    required this.barIndeterminateLabel,
    required this.barIndeterminateHint,
    required this.circularLabel,
    required this.circularHint,
    required this.stepsLabel,
    required this.stepsHint,
    required this.sliderAriaLabel,
  });

  final String description;
  final String barDeterminateLabel;
  final String barDeterminateHint;
  final String barIndeterminateLabel;
  final String barIndeterminateHint;
  final String circularLabel;
  final String circularHint;
  final String stepsLabel;
  final String stepsHint;
  final String sliderAriaLabel;
}

const _copyEn = _ProgressCopy(
  description: 'Bar, circular, and step indicators with tabular percent labels.',
  barDeterminateLabel: 'Bar · determinate',
  barDeterminateHint: 'variant="bar" showLabel',
  barIndeterminateLabel: 'Bar · indeterminate',
  barIndeterminateHint: 'indeterminate',
  circularLabel: 'Circular',
  circularHint: 'variant="circular"',
  stepsLabel: 'Steps',
  stepsHint: 'variant="steps" steps currentStep',
  sliderAriaLabel: 'Adjust progress value',
);

const _copyAr = _ProgressCopy(
  description: 'مؤشرات شريطية ودائرية وخطوات مع تسميات نسبة مئوية بأرقام متساوية العرض.',
  barDeterminateLabel: 'شريط · محدد',
  barDeterminateHint: 'variant="bar" showLabel',
  barIndeterminateLabel: 'شريط · غير محدد',
  barIndeterminateHint: 'indeterminate',
  circularLabel: 'دائري',
  circularHint: 'variant="circular"',
  stepsLabel: 'الخطوات',
  stepsHint: 'variant="steps" steps currentStep',
  sliderAriaLabel: 'ضبط قيمة التقدم',
);

_ProgressCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Progress showcase (web `ProgressShowcase`).
class ProgressShowcaseSection extends ConsumerStatefulWidget {
  const ProgressShowcaseSection({super.key});

  @override
  ConsumerState<ProgressShowcaseSection> createState() => _ProgressShowcaseSectionState();
}

class _ProgressShowcaseSectionState extends ConsumerState<ProgressShowcaseSection> {
  var _value = 62.0;

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'progress',
      title: 'Progress',
      description: copy.description,
      componentName: 'Progress',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShowcaseDemo(
            label: copy.barDeterminateLabel,
            propsHint: copy.barDeterminateHint,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppProgress(
                    variant: ProgressVariant.bar,
                    value: _value,
                    showLabel: true,
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  Semantics(
                    label: copy.sliderAriaLabel,
                    child: AppSlider(
                      valueDouble: _value,
                      min: 0,
                      max: 100,
                      step: 1,
                      showValue: false,
                      onChanged: (values) => setState(() => _value = values.first),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space6),
          ShowcaseDemoGrid(
            children: [
              ShowcaseDemo(
                label: copy.barIndeterminateLabel,
                propsHint: copy.barIndeterminateHint,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: AppProgress(
                    variant: ProgressVariant.bar,
                    indeterminate: true,
                  ),
                ),
              ),
              ShowcaseDemo(
                label: copy.circularLabel,
                propsHint: copy.circularHint,
                child: Wrap(
                  spacing: AppSpacing.space3,
                  runSpacing: AppSpacing.space3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppProgress(
                      variant: ProgressVariant.circular,
                      value: 75,
                    ),
                    AppProgress(
                      variant: ProgressVariant.circular,
                      value: 30,
                      size: ProgressSize.sm,
                    ),
                    AppProgress(
                      variant: ProgressVariant.circular,
                      indeterminate: true,
                    ),
                  ],
                ),
              ),
              ShowcaseDemo(
                label: copy.stepsLabel,
                propsHint: copy.stepsHint,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 384),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppProgress(
                        variant: ProgressVariant.steps,
                        steps: 5,
                        currentStep: 2,
                      ),
                      SizedBox(height: AppSpacing.space4),
                      AppProgress(
                        variant: ProgressVariant.steps,
                        steps: 4,
                        currentStep: 4,
                      ),
                    ],
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
