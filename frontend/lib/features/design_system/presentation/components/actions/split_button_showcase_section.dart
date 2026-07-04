import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_split_button.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

const _copy = {
  'en': {
    'exportReport': 'Export report',
    'saveChanges': 'Save changes',
    'saving': 'Saving…',
    'exportCsv': 'Export as CSV',
    'exportPdf': 'Export as PDF',
    'scheduleReport': 'Schedule report',
    'saveDraft': 'Save as draft',
    'copyConfig': 'Copy configuration',
  },
  'ar': {
    'exportReport': 'تصدير التقرير',
    'saveChanges': 'حفظ التغييرات',
    'saving': 'جارٍ الحفظ…',
    'exportCsv': 'تصدير CSV',
    'exportPdf': 'تصدير PDF',
    'scheduleReport': 'جدولة التقرير',
    'saveDraft': 'حفظ كمسودة',
    'copyConfig': 'نسخ الإعدادات',
  },
};

/// Split button showcase section (web `SplitButtonShowcase`).
class SplitButtonShowcaseSection extends ConsumerWidget {
  const SplitButtonShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(devPreviewProvider).locale;
    final t = _copy[locale] ?? _copy['en']!;

    return ShowcaseSection(
      id: 'split-button',
      title: 'Split button',
      description: 'Primary action plus related secondary actions. Chevron opens a motion-fade-scale menu.',
      componentName: 'AppSplitButton',
      child: ShowcaseDemoGrid(
        children: [
          ShowcaseDemo(
            label: 'Primary variant',
            propsHint: 'variant · items',
            child: AppSplitButton(
              label: t['exportReport']!,
              onPrimaryAction: () {},
              items: [
                SplitButtonMenuItem(id: 'csv', label: t['exportCsv']!),
                SplitButtonMenuItem(id: 'pdf', label: t['exportPdf']!),
                SplitButtonMenuItem(id: 'schedule', label: t['scheduleReport']!),
              ],
            ),
          ),
          ShowcaseDemo(
            label: 'Secondary variant',
            child: AppSplitButton(
              variant: AppButtonVariant.secondary,
              label: t['saveChanges']!,
              items: [
                SplitButtonMenuItem(id: 'draft', label: t['saveDraft']!),
                SplitButtonMenuItem(id: 'copy', label: t['copyConfig']!),
              ],
            ),
          ),
          ShowcaseDemo(
            label: 'Disabled',
            propsHint: 'disabled',
            child: AppSplitButton(
              disabled: true,
              label: t['exportReport']!,
              items: [SplitButtonMenuItem(id: 'csv', label: t['exportCsv']!)],
            ),
          ),
          ShowcaseDemo(
            label: 'Loading',
            propsHint: 'loading',
            child: AppSplitButton(
              loading: true,
              label: t['saving']!,
              items: [SplitButtonMenuItem(id: 'csv', label: t['exportCsv']!)],
            ),
          ),
        ],
      ),
    );
  }
}
