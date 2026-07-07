import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_toast.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

const _variants = <AppToastVariant>[
  AppToastVariant.success,
  AppToastVariant.danger,
  AppToastVariant.info,
  AppToastVariant.neutral,
];

class _ToastCopy {
  const _ToastCopy({
    required this.published,
    required this.couldNotSave,
    required this.syncInProgress,
    required this.draftSaved,
    required this.showVariant,
  });

  final String published;
  final String couldNotSave;
  final String syncInProgress;
  final String draftSaved;
  final String Function(String variant) showVariant;
}

const _copyEn = _ToastCopy(
  published: 'Published',
  couldNotSave: 'Could not save changes',
  syncInProgress: 'Sync in progress',
  draftSaved: 'Draft saved',
  showVariant: _showVariantEn,
);

const _copyAr = _ToastCopy(
  published: 'تم النشر',
  couldNotSave: 'تعذر حفظ التغييرات',
  syncInProgress: 'المزامنة قيد التنفيذ',
  draftSaved: 'تم حفظ المسودة',
  showVariant: _showVariantAr,
);

String _showVariantEn(String variant) => 'Show $variant';

String _showVariantAr(String variant) => 'عرض $variant';

_ToastCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

String _messageFor(AppToastVariant variant, _ToastCopy copy) {
  return switch (variant) {
    AppToastVariant.success => copy.published,
    AppToastVariant.danger => copy.couldNotSave,
    AppToastVariant.info => copy.syncInProgress,
    AppToastVariant.neutral => copy.draftSaved,
  };
}

String _variantLabel(AppToastVariant variant) {
  return switch (variant) {
    AppToastVariant.success => 'success',
    AppToastVariant.danger => 'danger',
    AppToastVariant.info => 'info',
    AppToastVariant.neutral => 'neutral',
  };
}

class ToastShowcaseSection extends ConsumerWidget {
  const ToastShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'toast',
      title: 'Toast',
      componentName: 'useToast / ToastProvider',
      child: ShowcaseDemoGrid(
        columns: 2,
        children: [
          for (final variant in _variants)
            ShowcaseDemo(
              label: _variantLabel(variant),
              child: AppButton(
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                onPressed: () {
                  appToast(
                    context,
                    AppToastInput(
                      variant: variant,
                      message: _messageFor(variant, copy),
                      action: variant == AppToastVariant.success
                          ? const AppToastAction(label: 'Undo', onPressed: _noop)
                          : null,
                    ),
                  );
                },
                child: Text(copy.showVariant(_variantLabel(variant))),
              ),
            ),
        ],
      ),
    );
  }
}

void _noop() {}
