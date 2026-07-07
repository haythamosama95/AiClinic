import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

const _variants = <AppButtonVariant>[
  AppButtonVariant.primary,
  AppButtonVariant.secondary,
  AppButtonVariant.ghost,
  AppButtonVariant.danger,
  AppButtonVariant.ai,
  AppButtonVariant.link,
];

const _sizes = <AppButtonSize>[AppButtonSize.sm, AppButtonSize.md, AppButtonSize.lg];

class _ButtonCopy {
  const _ButtonCopy({
    required this.addService,
    required this.saveChanges,
    required this.deleteService,
    required this.askAi,
    required this.viewDetails,
    required this.publish,
    required this.saving,
    required this.addPatient,
    required this.scheduleView,
  });

  final String addService;
  final String saveChanges;
  final String deleteService;
  final String askAi;
  final String viewDetails;
  final String publish;
  final String saving;
  final String addPatient;
  final String scheduleView;
}

const _copyEn = _ButtonCopy(
  addService: 'Add service',
  saveChanges: 'Save changes',
  deleteService: 'Delete service',
  askAi: 'Ask AI',
  viewDetails: 'View details',
  publish: 'Publish',
  saving: 'Saving…',
  addPatient: 'Add patient',
  scheduleView: 'Schedule view',
);

const _copyAr = _ButtonCopy(
  addService: 'إضافة خدمة',
  saveChanges: 'حفظ التغييرات',
  deleteService: 'حذف الخدمة',
  askAi: 'اسأل الذكاء الاصطناعي',
  viewDetails: 'عرض التفاصيل',
  publish: 'نشر',
  saving: 'جارٍ الحفظ…',
  addPatient: 'إضافة مريض',
  scheduleView: 'عرض الجدول',
);

_ButtonCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

String _labelForVariant(AppButtonVariant variant, _ButtonCopy copy) {
  return switch (variant) {
    AppButtonVariant.primary => copy.addService,
    AppButtonVariant.secondary => copy.saveChanges,
    AppButtonVariant.ghost => copy.viewDetails,
    AppButtonVariant.danger => copy.deleteService,
    AppButtonVariant.ai => copy.askAi,
    AppButtonVariant.link => copy.viewDetails,
  };
}

/// Button component matrix (web `ButtonShowcase`).
class ButtonShowcaseSection extends ConsumerStatefulWidget {
  const ButtonShowcaseSection({super.key});

  @override
  ConsumerState<ButtonShowcaseSection> createState() => _ButtonShowcaseSectionState();
}

class _ButtonShowcaseSectionState extends ConsumerState<ButtonShowcaseSection> {
  var _loadingDemo = false;

  void _simulateLoading() {
    setState(() => _loadingDemo = true);
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _loadingDemo = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'button',
      title: 'Button',
      description:
          'Trigger an action. Labels are verbs; one primary per view region. Press scales to 0.98.',
      componentName: 'Button',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShowcaseDemoGrid(
            columns: 2,
            children: [
              ShowcaseDemo(
                label: 'Variants',
                propsHint: 'variant · size="md"',
                child: ShowcaseVariantMatrix(
                  title: 'All variants',
                  children: [
                    for (final variant in _variants)
                      AppButton(
                        variant: variant,
                        leadingIcon: variant == AppButtonVariant.ai
                            ? const Icon(Icons.auto_awesome_outlined)
                            : variant == AppButtonVariant.primary
                            ? const Icon(Icons.add)
                            : null,
                        child: Text(_labelForVariant(variant, copy)),
                      ),
                  ],
                ),
              ),
              ShowcaseDemo(
                label: 'Sizes',
                propsHint: 'variant="primary"',
                child: ShowcaseVariantMatrix(
                  title: 'sm · md · lg',
                  children: [
                    for (final size in _sizes)
                      AppButton(
                        size: size,
                        leadingIcon: Icon(Icons.add, size: size == AppButtonSize.lg ? 20 : 16),
                        child: Text(copy.addService),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space8),
          ShowcaseDemoGrid(
            columns: 2,
            children: [
              ShowcaseDemo(
                label: 'Disabled',
                propsHint: 'disabled',
                child: Wrap(
                  spacing: AppSpacing.space3,
                  runSpacing: AppSpacing.space3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppButton(disabled: true, child: Text(copy.publish)),
                    AppButton(variant: AppButtonVariant.secondary, disabled: true, child: Text(copy.saveChanges)),
                    AppButton(variant: AppButtonVariant.danger, disabled: true, child: Text(copy.deleteService)),
                  ],
                ),
              ),
              ShowcaseDemo(
                label: 'Loading',
                propsHint: 'loading · aria-busy',
                child: Wrap(
                  spacing: AppSpacing.space3,
                  runSpacing: AppSpacing.space3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppButton(loading: true, child: Text(copy.saving)),
                    AppButton(
                      loading: _loadingDemo,
                      onPressed: _simulateLoading,
                      child: Text(_loadingDemo ? copy.saving : copy.publish),
                    ),
                  ],
                ),
              ),
              ShowcaseDemo(
                label: 'Error',
                propsHint: 'error · aria-invalid',
                child: Wrap(
                  spacing: AppSpacing.space3,
                  runSpacing: AppSpacing.space3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppButton(error: true, child: Text(copy.publish)),
                    AppButton(variant: AppButtonVariant.secondary, error: true, child: Text(copy.saveChanges)),
                  ],
                ),
              ),
              ShowcaseDemo(
                label: 'With icons',
                propsHint: 'leadingIcon · trailingIcon',
                child: Wrap(
                  spacing: AppSpacing.space3,
                  runSpacing: AppSpacing.space3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppButton(leadingIcon: const Icon(Icons.add), child: Text(copy.addPatient)),
                    AppButton(
                      variant: AppButtonVariant.secondary,
                      trailingIcon: const Icon(Icons.calendar_today_outlined),
                      child: Text(copy.scheduleView),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
