import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_phone_input.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _PhoneInputCopy {
  const _PhoneInputCopy({
    required this.mobileNumber,
    required this.helper,
    required this.description,
  });

  final String mobileNumber;
  final String helper;
  final String description;
}

const _copyEn = _PhoneInputCopy(
  mobileNumber: 'Mobile number',
  helper: 'Validates shape, not carrier.',
  description: 'Egypt (+20) default, formats as typed, Latin digits.',
);

const _copyAr = _PhoneInputCopy(
  mobileNumber: 'رقم الجوال',
  helper: 'يتحقق من الشكل، وليس من مزود الخدمة.',
  description: 'مصر (+20) افتراضيًا، تنسيق أثناء الكتابة، أرقام لاتينية.',
);

_PhoneInputCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Phone input showcase (web `PhoneInputShowcase`).
class PhoneInputShowcaseSection extends ConsumerWidget {
  const PhoneInputShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    const fieldId = 'phone-input-mobile';

    return ShowcaseSection(
      id: 'phone-input',
      title: 'Phone input',
      componentName: 'PhoneInput',
      description: copy.description,
      child: AppFormField(
        id: fieldId,
        label: copy.mobileNumber,
        helperText: copy.helper,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: AppPhoneInput(id: fieldId),
        ),
      ),
    );
  }
}
