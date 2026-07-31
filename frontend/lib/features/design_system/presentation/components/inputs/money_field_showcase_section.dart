import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_money_field.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _MoneyFieldCopy {
  const _MoneyFieldCopy({
    required this.defaultPrice,
    required this.description,
  });

  final String defaultPrice;
  final String description;
}

const _copyEn = _MoneyFieldCopy(
  defaultPrice: 'Default price',
  description: 'EGP affix, tabular figures, 2-decimal scale, thousands grouping on blur.',
);

const _copyAr = _MoneyFieldCopy(
  defaultPrice: 'السعر الافتراضي',
  description: 'لاحقة EGP، أرقام جدولية، مقياس عشري مزدوج، تجميع الآلاف عند فقدان التركيز.',
);

_MoneyFieldCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Money field showcase (web `MoneyFieldShowcase`).
class MoneyFieldShowcaseSection extends ConsumerWidget {
  const MoneyFieldShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final locale = ref.watch(devPreviewProvider).locale == 'ar' ? 'ar-EG' : 'en-EG';
    const defaultFieldId = 'money-field-default';
    const invalidFieldId = 'money-field-invalid';

    return ShowcaseSection(
      id: 'money-field',
      title: 'Money field',
      componentName: 'MoneyField',
      description: copy.description,
      child: ShowcaseDemoGrid(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: AppFormField(
              id: defaultFieldId,
              label: copy.defaultPrice,
              requiredMark: true,
              child: AppMoneyField(
                id: defaultFieldId,
                initialValue: 350,
                locale: locale,
              ),
            ),
          ),
          ShowcaseDemo(
            label: 'Invalid',
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: AppMoneyField(
                id: invalidFieldId,
                invalid: true,
                initialValue: -10,
                locale: locale,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
