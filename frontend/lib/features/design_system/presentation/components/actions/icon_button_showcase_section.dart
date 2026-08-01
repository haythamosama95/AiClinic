import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

const _copy = {
  'en': {
    'addPatient': 'Add patient',
    'deleteRow': 'Delete row',
    'editAppointment': 'Edit appointment',
    'askAi': 'Ask AI',
  },
  'ar': {
    'addPatient': 'إضافة مريض',
    'deleteRow': 'حذف الصف',
    'editAppointment': 'تعديل الموعد',
    'askAi': 'اسأل الذكاء الاصطناعي',
  },
};

/// Icon button showcase section (web `IconButtonShowcase`).
class IconButtonShowcaseSection extends ConsumerWidget {
  const IconButtonShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(devPreviewProvider).locale;
    final t = _copy[locale] ?? _copy['en']!;

    return ShowcaseSection(
      id: 'icon-button',
      title: 'Icon button',
      description: 'Compact actions for toolbars and row actions. aria-label and tooltip required.',
      componentName: 'AppIconButton',
      child: ShowcaseDemoGrid(
        children: [
          ShowcaseDemo(
            label: 'Variants',
            propsHint: 'ghost · secondary · danger · ai',
            child: ShowcaseVariantMatrix(
              title: 'All variants',
              children: [
                AppIconButton(
                  label: t['addPatient']!,
                  icon: const Icon(Icons.add),
                  onPressed: () {},
                ),
                AppIconButton(
                  variant: AppIconButtonVariant.secondary,
                  label: t['editAppointment']!,
                  icon: const Icon(Icons.calendar_today),
                  onPressed: () {},
                ),
                AppIconButton(
                  variant: AppIconButtonVariant.danger,
                  label: t['deleteRow']!,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {},
                ),
                AppIconButton(
                  variant: AppIconButtonVariant.ai,
                  label: t['askAi']!,
                  icon: const Icon(Icons.auto_awesome),
                  onPressed: () {},
                ),
              ],
            ),
          ),
          ShowcaseDemo(
            label: 'Sizes',
            propsHint: 'sm · md · lg',
            child: Wrap(
              spacing: 12,
              children: [
                AppIconButton(
                  size: AppIconButtonSize.sm,
                  label: t['addPatient']!,
                  icon: const Icon(Icons.add),
                  onPressed: () {},
                ),
                AppIconButton(
                  size: AppIconButtonSize.md,
                  label: t['addPatient']!,
                  icon: const Icon(Icons.add),
                  onPressed: () {},
                ),
                AppIconButton(
                  size: AppIconButtonSize.lg,
                  label: t['addPatient']!,
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () {},
                ),
              ],
            ),
          ),
          ShowcaseDemo(
            label: 'Disabled',
            propsHint: 'disabled',
            child: AppIconButton(
              label: t['deleteRow']!,
              icon: const Icon(Icons.delete_outline),
              onPressed: null,
            ),
          ),
          ShowcaseDemo(
            label: 'Error',
            propsHint: 'error',
            child: AppIconButton(
              label: t['deleteRow']!,
              icon: const Icon(Icons.delete_outline),
              error: true,
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }
}
