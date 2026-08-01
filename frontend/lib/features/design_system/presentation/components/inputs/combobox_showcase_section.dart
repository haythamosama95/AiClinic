import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_combobox.dart';
import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _ComboboxCopy {
  const _ComboboxCopy({
    required this.description,
    required this.asyncLabel,
    required this.asyncHelper,
    required this.asyncPlaceholder,
    required this.staticLabel,
    required this.staticPlaceholder,
    required this.emptyPlaceholder,
    required this.catalog,
  });

  final String description;
  final String asyncLabel;
  final String asyncHelper;
  final String asyncPlaceholder;
  final String staticLabel;
  final String staticPlaceholder;
  final String emptyPlaceholder;
  final List<AppComboboxItem> catalog;
}

const _mockCatalogEn = [
  AppComboboxItem(id: '1', label: 'Ahmed Hassan', meta: 'Patient · #1042', initials: 'AH'),
  AppComboboxItem(id: '2', label: 'Consultation', meta: 'Service · EGP 350', initials: 'CO'),
  AppComboboxItem(
    id: '3',
    label: 'Blood panel',
    meta: 'Service · inactive',
    initials: 'BP',
    disabled: true,
    disabledReason: 'Inactive service',
  ),
  AppComboboxItem(id: '4', label: 'Dr. Nadia El-Sayed', meta: 'Doctor · Cardiology', initials: 'NE'),
];

const _mockCatalogAr = [
  AppComboboxItem(id: '1', label: 'أحمد حسن', meta: 'مريض · #1042', initials: 'أح'),
  AppComboboxItem(id: '2', label: 'استشارة', meta: 'خدمة · 350 جنيه', initials: 'اس'),
  AppComboboxItem(
    id: '3',
    label: 'تحليل دم',
    meta: 'خدمة · غير نشطة',
    initials: 'تح',
    disabled: true,
    disabledReason: 'خدمة غير نشطة',
  ),
  AppComboboxItem(id: '4', label: 'د. نادية السيد', meta: 'طبيب · قلب', initials: 'ند'),
];

const _copyEn = _ComboboxCopy(
  description: 'Async search, empty state, match highlight, and ineligible items with reason.',
  asyncLabel: 'Search catalog (async)',
  asyncHelper: 'Debounced async search with loading state.',
  asyncPlaceholder: 'Search patients or services',
  staticLabel: 'Static list (ineligible item)',
  staticPlaceholder: 'Pick from catalog',
  emptyPlaceholder: 'Type to see empty state',
  catalog: _mockCatalogEn,
);

const _copyAr = _ComboboxCopy(
  description: 'بحث غير متزامن، حالة فارغة، تمييز التطابق، وعناصر غير مؤهلة مع السبب.',
  asyncLabel: 'بحث في الكتالوج (غير متزامن)',
  asyncHelper: 'بحث غير متزامن مع تأخير وحالة تحميل.',
  asyncPlaceholder: 'ابحث عن مرضى أو خدمات',
  staticLabel: 'قائمة ثابتة (عنصر غير مؤهل)',
  staticPlaceholder: 'اختر من الكتالوج',
  emptyPlaceholder: 'اكتب لرؤية الحالة الفارغة',
  catalog: _mockCatalogAr,
);

_ComboboxCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

Future<List<AppComboboxItem>> _mockAsyncSearch(List<AppComboboxItem> catalog, String query) async {
  await Future<void>.delayed(const Duration(milliseconds: 600));
  if (!query.trim().isNotEmpty) return catalog.take(3).toList();
  final lower = query.toLowerCase();
  return catalog
      .where((item) => item.label.toLowerCase().contains(lower) || (item.meta?.toLowerCase().contains(lower) ?? false))
      .toList();
}

/// Combobox showcase (web `ComboboxShowcase`).
class ComboboxShowcaseSection extends ConsumerStatefulWidget {
  const ComboboxShowcaseSection({super.key});

  @override
  ConsumerState<ComboboxShowcaseSection> createState() => _ComboboxShowcaseSectionState();
}

class _ComboboxShowcaseSectionState extends ConsumerState<ComboboxShowcaseSection> {
  AppComboboxItem? _asyncValue;
  AppComboboxItem? _staticValue;

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    const asyncId = 'combobox-async';
    const staticId = 'combobox-static';

    return ShowcaseSection(
      id: 'combobox',
      title: 'Combobox / autocomplete',
      componentName: 'Combobox',
      description: copy.description,
      child: ShowcaseDemoGrid(
        children: [
          AppFormField(
            id: asyncId,
            label: copy.asyncLabel,
            helperText: copy.asyncHelper,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: AppCombobox(
                id: asyncId,
                placeholder: copy.asyncPlaceholder,
                value: _asyncValue,
                onValueChange: (value) => setState(() => _asyncValue = value),
                onSearch: (query) => _mockAsyncSearch(copy.catalog, query),
              ),
            ),
          ),
          AppFormField(
            id: staticId,
            label: copy.staticLabel,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: AppCombobox(
                id: staticId,
                placeholder: copy.staticPlaceholder,
                items: copy.catalog,
                value: _staticValue,
                onValueChange: (value) => setState(() => _staticValue = value),
              ),
            ),
          ),
          ShowcaseDemo(
            label: 'Empty results',
            propsHint: 'onSearch → []',
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: AppCombobox(
                items: const [],
                placeholder: copy.emptyPlaceholder,
                onSearch: (_) async {
                  await Future<void>.delayed(const Duration(milliseconds: 400));
                  return [];
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
