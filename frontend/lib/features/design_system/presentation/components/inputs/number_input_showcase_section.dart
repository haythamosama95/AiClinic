import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_number_input.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _NumberInputCopy {
  const _NumberInputCopy({
    required this.quantityLabel,
    required this.quantityHelper,
  });

  final String quantityLabel;
  final String quantityHelper;
}

const _copyEn = _NumberInputCopy(
  quantityLabel: 'Quantity',
  quantityHelper: 'Defaults to 1 for invoice items.',
);

const _copyAr = _NumberInputCopy(
  quantityLabel: 'الكمية',
  quantityHelper: 'القيمة الافتراضية 1 لبنود الفاتورة.',
);

_NumberInputCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Number / stepper showcase (web `NumberInputShowcase`).
class NumberInputShowcaseSection extends ConsumerWidget {
  const NumberInputShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    const quantityId = 'number-input-demo';

    return ShowcaseSection(
      id: 'number-input',
      title: 'Number / stepper',
      description: 'Tabular figures with optional +/− steppers and min/max.',
      componentName: 'NumberInput',
      child: AppFormField(
        id: quantityId,
        label: copy.quantityLabel,
        helperText: copy.quantityHelper,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: AppNumberInput(
            id: quantityId,
            initialValue: 1,
            min: 1,
            max: 99,
          ),
        ),
      ),
    );
  }
}
