import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _FormFieldCopy {
  const _FormFieldCopy({
    required this.defaultLabel,
    required this.defaultHelper,
    required this.defaultPlaceholder,
    required this.errorLabel,
    required this.errorHint,
    required this.errorMessage,
    required this.errorValue,
  });

  final String defaultLabel;
  final String defaultHelper;
  final String defaultPlaceholder;
  final String errorLabel;
  final String errorHint;
  final String errorMessage;
  final String errorValue;
}

const _copyEn = _FormFieldCopy(
  defaultLabel: 'Default price',
  defaultHelper: 'Used when a branch has no price override.',
  defaultPlaceholder: 'e.g. 350.00',
  errorLabel: 'Service name',
  errorHint: 'Must be unique within your organization.',
  errorMessage: 'A service with this name already exists in your organization.',
  errorValue: 'Consultation',
);

const _copyAr = _FormFieldCopy(
  defaultLabel: 'السعر الافتراضي',
  defaultHelper: 'يُستخدم عندما لا يوجد سعر مخصص للفرع.',
  defaultPlaceholder: 'مثال: 350.00',
  errorLabel: 'اسم الخدمة',
  errorHint: 'يجب أن يكون فريدًا داخل مؤسستك.',
  errorMessage: 'توجد خدمة بهذا الاسم بالفعل في مؤسستك.',
  errorValue: 'استشارة',
);

_FormFieldCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Form field showcase (web `FormFieldShowcase`).
class FormFieldShowcaseSection extends ConsumerWidget {
  const FormFieldShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'form-field',
      title: 'Form field',
      description: 'Label, required mark, hint tooltip, helper text, and error scaffold.',
      componentName: 'FormField',
      child: ShowcaseDemoGrid(
        children: [
          AppFormField(
            id: 'form-field-default',
            label: copy.defaultLabel,
            helperText: copy.defaultHelper,
            child: AppTextInput(
              id: 'form-field-default',
              placeholder: copy.defaultPlaceholder,
            ),
          ),
          AppFormField(
            id: 'form-field-error',
            label: copy.errorLabel,
            requiredMark: true,
            hint: copy.errorHint,
            error: copy.errorMessage,
            child: AppTextInput(
              id: 'form-field-error',
              invalid: true,
              initialValue: copy.errorValue,
            ),
          ),
        ],
      ),
    );
  }
}
