import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_popover.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _PopoverCopy {
  const _PopoverCopy({
    required this.openPopover,
    required this.content,
  });

  final String openPopover;
  final String content;
}

const _copyEn = _PopoverCopy(
  openPopover: 'Open popover',
  content: 'Quick edit or filter content.',
);

const _copyAr = _PopoverCopy(
  openPopover: 'فتح النافذة المنبثقة',
  content: 'محتوى تعديل سريع أو تصفية.',
);

_PopoverCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Popover showcase (web `PopoverShowcase`).
class PopoverShowcaseSection extends ConsumerWidget {
  const PopoverShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'popover',
      title: 'Popover',
      componentName: 'Popover',
      child: AppPopover(
        triggerBuilder: (context, isOpen, onToggle) => AppButton(
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.sm,
          onPressed: onToggle,
          child: Text(copy.openPopover),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: Text(
            copy.content,
            style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}
