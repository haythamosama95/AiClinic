import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_slider.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _SliderCopy {
  const _SliderCopy({
    required this.coverageLabel,
    required this.coverageHelper,
    required this.description,
  });

  final String coverageLabel;
  final String coverageHelper;
  final String description;
}

const _copyEn = _SliderCopy(
  coverageLabel: 'Insurance coverage',
  coverageHelper: 'Rare — used for coverage percentage.',
  description: 'Coverage percentage with tabular value label and keyboard arrows.',
);

const _copyAr = _SliderCopy(
  coverageLabel: 'تغطية التأمين',
  coverageHelper: 'نادر — يُستخدم لنسبة التغطية.',
  description: 'نسبة التغطية مع تسمية قيمة بأرقام متساوية العرض وأسهم لوحة المفاتيح.',
);

_SliderCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Slider showcase (web `SliderShowcase`).
class SliderShowcaseSection extends ConsumerWidget {
  const SliderShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    const fieldId = 'slider-coverage';

    return ShowcaseSection(
      id: 'slider',
      title: 'Slider',
      componentName: 'Slider',
      description: copy.description,
      child: AppFormField(
        id: fieldId,
        label: copy.coverageLabel,
        helperText: copy.coverageHelper,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 448),
          child: AppSlider(
            id: fieldId,
            ariaLabelledBy: copy.coverageLabel,
            defaultValue: const [75],
          ),
        ),
      ),
    );
  }
}
