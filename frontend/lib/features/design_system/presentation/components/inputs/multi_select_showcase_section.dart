import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_combobox.dart';
import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_multi_select.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _MultiSelectCopy {
  const _MultiSelectCopy({
    required this.description,
    required this.label,
    required this.helper,
    required this.allBranches,
    required this.options,
  });

  final String description;
  final String label;
  final String helper;
  final String allBranches;
  final List<AppComboboxItem> options;
}

const _optionsEn = [
  AppComboboxItem(id: 'main', label: 'Main branch', meta: 'Cairo'),
  AppComboboxItem(id: 'downtown', label: 'Downtown', meta: 'Giza'),
  AppComboboxItem(id: 'north', label: 'North clinic', meta: 'Alexandria'),
];

const _optionsAr = [
  AppComboboxItem(id: 'main', label: 'الفرع الرئيسي', meta: 'القاهرة'),
  AppComboboxItem(id: 'downtown', label: 'وسط المدينة', meta: 'الجيزة'),
  AppComboboxItem(id: 'north', label: 'عيادة الشمال', meta: 'الإسكندرية'),
];

const _copyEn = _MultiSelectCopy(
  description: 'Removable chips inside the field with combobox popover and All branches option.',
  label: 'Selected branches',
  helper: 'Use "All branches" for org-wide access.',
  allBranches: 'All branches',
  options: _optionsEn,
);

const _copyAr = _MultiSelectCopy(
  description: 'رقائق قابلة للإزالة داخل الحقل مع قائمة منبثقة وخيار كل الفروع.',
  label: 'الفروع المحددة',
  helper: 'استخدم "كل الفروع" للوصول على مستوى المؤسسة.',
  allBranches: 'كل الفروع',
  options: _optionsAr,
);

_MultiSelectCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Multi-select showcase (web `MultiSelectShowcase`).
class MultiSelectShowcaseSection extends ConsumerStatefulWidget {
  const MultiSelectShowcaseSection({super.key});

  @override
  ConsumerState<MultiSelectShowcaseSection> createState() => _MultiSelectShowcaseSectionState();
}

class _MultiSelectShowcaseSectionState extends ConsumerState<MultiSelectShowcaseSection> {
  List<AppComboboxItem> _value = [];

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    const fieldId = 'multi-select-branches';

    return ShowcaseSection(
      id: 'multi-select',
      title: 'Multi-select / token',
      componentName: 'MultiSelect',
      description: copy.description,
      child: AppFormField(
        id: fieldId,
        label: copy.label,
        helperText: copy.helper,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 448),
          child: AppMultiSelect(
            id: fieldId,
            options: copy.options,
            value: _value,
            onValueChange: (next) => setState(() => _value = next),
            allLabel: copy.allBranches,
          ),
        ),
      ),
    );
  }
}
