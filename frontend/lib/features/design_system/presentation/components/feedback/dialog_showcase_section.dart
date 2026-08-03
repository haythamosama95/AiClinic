import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_dialog.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _DialogCopy {
  const _DialogCopy({
    required this.small,
    required this.medium,
    required this.large,
    required this.full,
    required this.destructive,
    required this.financial,
    required this.smallTitle,
    required this.mediumTitle,
    required this.largeTitle,
    required this.fullTitle,
    required this.smallBody,
    required this.mediumBody,
    required this.largeBody,
    required this.fullBody,
    required this.close,
    required this.save,
    required this.done,
    required this.archiveTitle,
    required this.archiveDescription,
    required this.archiveConfirm,
    required this.voidTitle,
    required this.voidDescription,
    required this.voidConfirm,
  });

  final String small;
  final String medium;
  final String large;
  final String full;
  final String destructive;
  final String financial;
  final String smallTitle;
  final String mediumTitle;
  final String largeTitle;
  final String fullTitle;
  final String smallBody;
  final String mediumBody;
  final String largeBody;
  final String fullBody;
  final String close;
  final String save;
  final String done;
  final String archiveTitle;
  final String archiveDescription;
  final String archiveConfirm;
  final String voidTitle;
  final String voidDescription;
  final String voidConfirm;
}

const _copyEn = _DialogCopy(
  small: 'Small',
  medium: 'Medium',
  large: 'Large',
  full: 'Full',
  destructive: 'Destructive',
  financial: 'Financial',
  smallTitle: 'Small dialog',
  mediumTitle: 'Medium dialog',
  largeTitle: 'Large dialog',
  fullTitle: 'Full dialog',
  smallBody: 'Focused decision or short form.',
  mediumBody: 'Default size for create/edit forms.',
  largeBody: 'More room for complex forms.',
  fullBody: 'Rare full-screen modal.',
  close: 'Close',
  save: 'Save',
  done: 'Done',
  archiveTitle: 'Archive patient?',
  archiveDescription: 'This removes the patient from active lists. Visit history is retained.',
  archiveConfirm: 'Archive',
  voidTitle: 'Void invoice INV-2026-0842?',
  voidDescription: 'This voids EGP 1,850.00 and cannot be undone.',
  voidConfirm: 'Void invoice',
);

const _copyAr = _DialogCopy(
  small: 'صغير',
  medium: 'متوسط',
  large: 'كبير',
  full: 'كامل',
  destructive: 'مدمر',
  financial: 'مالي',
  smallTitle: 'حوار صغير',
  mediumTitle: 'حوار متوسط',
  largeTitle: 'حوار كبير',
  fullTitle: 'حوار كامل الشاشة',
  smallBody: 'قرار مركّز أو نموذج قصير.',
  mediumBody: 'الحجم الافتراضي لنماذج الإنشاء والتعديل.',
  largeBody: 'مساحة أكبر للنماذج المعقدة.',
  fullBody: 'نافذة نادرة بحجم الشاشة الكاملة.',
  close: 'إغلاق',
  save: 'حفظ',
  done: 'تم',
  archiveTitle: 'أرشفة المريض؟',
  archiveDescription: 'يزيل المريض من القوائم النشطة. يُحتفظ بسجل الزيارات.',
  archiveConfirm: 'أرشفة',
  voidTitle: 'إلغاء الفاتورة INV-2026-0842؟',
  voidDescription: 'يلغي هذا 1,850.00 جنيه مصري ولا يمكن التراجع.',
  voidConfirm: 'إلغاء الفاتورة',
);

_DialogCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Dialog component showcase (web `DialogShowcase`).
class DialogShowcaseSection extends ConsumerStatefulWidget {
  const DialogShowcaseSection({super.key});

  @override
  ConsumerState<DialogShowcaseSection> createState() => _DialogShowcaseSectionState();
}

class _DialogShowcaseSectionState extends ConsumerState<DialogShowcaseSection> {
  var _openSm = false;
  var _openMd = false;
  var _openLg = false;
  var _openFull = false;
  var _confirmOpen = false;
  var _financialOpen = false;

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;
    final bodyStyle = AppTypography.body(context).copyWith(color: colors.textSecondary);

    return ShowcaseSection(
      id: 'dialog',
      title: 'Dialog',
      componentName: 'Dialog / ConfirmationDialog',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShowcaseDemoGrid(
            columns: 2,
            children: [
              ShowcaseDemo(
                label: 'Sizes',
                child: Wrap(
                  spacing: AppSpacing.space2,
                  runSpacing: AppSpacing.space2,
                  children: [
                    AppButton(
                      size: AppButtonSize.sm,
                      onPressed: () => setState(() => _openSm = true),
                      child: Text(copy.small),
                    ),
                    AppButton(
                      size: AppButtonSize.sm,
                      onPressed: () => setState(() => _openMd = true),
                      child: Text(copy.medium),
                    ),
                    AppButton(
                      size: AppButtonSize.sm,
                      onPressed: () => setState(() => _openLg = true),
                      child: Text(copy.large),
                    ),
                    AppButton(
                      size: AppButtonSize.sm,
                      onPressed: () => setState(() => _openFull = true),
                      child: Text(copy.full),
                    ),
                  ],
                ),
              ),
              ShowcaseDemo(
                label: 'Confirmation',
                child: Wrap(
                  spacing: AppSpacing.space2,
                  runSpacing: AppSpacing.space2,
                  children: [
                    AppButton(
                      variant: AppButtonVariant.danger,
                      size: AppButtonSize.sm,
                      onPressed: () => setState(() => _confirmOpen = true),
                      child: Text(copy.destructive),
                    ),
                    AppButton(
                      size: AppButtonSize.sm,
                      onPressed: () => setState(() => _financialOpen = true),
                      child: Text(copy.financial),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppDialog(
            open: _openSm,
            onOpenChange: (open) => setState(() => _openSm = open),
            title: copy.smallTitle,
            size: AppDialogSize.sm,
            footer: AppButton(
              onPressed: () => setState(() => _openSm = false),
              child: Text(copy.close),
            ),
            child: Text(copy.smallBody, style: bodyStyle),
          ),
          AppDialog(
            open: _openMd,
            onOpenChange: (open) => setState(() => _openMd = open),
            title: copy.mediumTitle,
            size: AppDialogSize.md,
            footer: AppButton(
              onPressed: () => setState(() => _openMd = false),
              child: Text(copy.save),
            ),
            child: Text(copy.mediumBody, style: bodyStyle),
          ),
          AppDialog(
            open: _openLg,
            onOpenChange: (open) => setState(() => _openLg = open),
            title: copy.largeTitle,
            size: AppDialogSize.lg,
            footer: AppButton(
              onPressed: () => setState(() => _openLg = false),
              child: Text(copy.done),
            ),
            child: Text(copy.largeBody, style: bodyStyle),
          ),
          AppDialog(
            open: _openFull,
            onOpenChange: (open) => setState(() => _openFull = open),
            title: copy.fullTitle,
            size: AppDialogSize.full,
            footer: AppButton(
              onPressed: () => setState(() => _openFull = false),
              child: Text(copy.close),
            ),
            child: Text(copy.fullBody, style: bodyStyle),
          ),
          AppConfirmationDialog(
            open: _confirmOpen,
            onOpenChange: (open) => setState(() => _confirmOpen = open),
            title: copy.archiveTitle,
            description: copy.archiveDescription,
            confirmLabel: copy.archiveConfirm,
            variant: AppConfirmationDialogVariant.destructive,
            requireTypedConfirmation: 'ARCHIVE',
            onConfirm: () {},
          ),
          AppConfirmationDialog(
            open: _financialOpen,
            onOpenChange: (open) => setState(() => _financialOpen = open),
            title: copy.voidTitle,
            description: copy.voidDescription,
            confirmLabel: copy.voidConfirm,
            variant: AppConfirmationDialogVariant.financial,
            onConfirm: () {},
          ),
        ],
      ),
    );
  }
}
