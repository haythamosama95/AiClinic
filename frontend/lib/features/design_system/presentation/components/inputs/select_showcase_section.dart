import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_select.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _SelectCopy {
  const _SelectCopy({
    required this.branchLabel,
    required this.placeholder,
    required this.description,
    required this.mainBranch,
    required this.downtown,
    required this.northClinic,
    required this.disabledReason,
  });

  final String branchLabel;
  final String placeholder;
  final String description;
  final String mainBranch;
  final String downtown;
  final String northClinic;
  final String disabledReason;
}

const _copyEn = _SelectCopy(
  branchLabel: 'Branch',
  placeholder: 'Choose a branch',
  description: 'Single choice dropdown with keyboard type-ahead and motion-fade-scale menu.',
  mainBranch: 'Main branch',
  downtown: 'Downtown',
  northClinic: 'North clinic',
  disabledReason: 'Temporarily closed',
);

const _copyAr = _SelectCopy(
  branchLabel: 'الفرع',
  placeholder: 'اختر فرعًا',
  description: 'قائمة منسدلة لاختيار واحد مع كتابة سريعة وقائمة بحركة تلاشٍ-تكبير.',
  mainBranch: 'الفرع الرئيسي',
  downtown: 'وسط المدينة',
  northClinic: 'عيادة الشمال',
  disabledReason: 'مغلق مؤقتًا',
);

_SelectCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

List<AppSelectOption> _optionsFor(_SelectCopy copy) => [
  AppSelectOption(value: 'main', label: copy.mainBranch),
  AppSelectOption(value: 'downtown', label: copy.downtown),
  AppSelectOption(
    value: 'north',
    label: copy.northClinic,
    disabled: true,
    disabledReason: copy.disabledReason,
  ),
];

/// Select showcase (web `SelectShowcase`).
class SelectShowcaseSection extends ConsumerWidget {
  const SelectShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    const fieldId = 'select-branch';

    return ShowcaseSection(
      id: 'select',
      title: 'Select',
      componentName: 'Select',
      description: copy.description,
      child: AppFormField(
        id: fieldId,
        label: copy.branchLabel,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: AppSelect(
            id: fieldId,
            options: _optionsFor(copy),
            placeholder: copy.placeholder,
          ),
        ),
      ),
    );
  }
}
