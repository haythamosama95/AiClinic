import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_kbd.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/command_bar_controller.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _CommandBarCopy {
  const _CommandBarCopy({
    required this.description,
    required this.label,
    required this.propsHint,
    required this.trigger,
    required this.hintPrefix,
    required this.hintSuffix,
  });

  final String description;
  final String label;
  final String propsHint;
  final String trigger;
  final String hintPrefix;
  final String hintSuffix;
}

const _copyEn = _CommandBarCopy(
  description: 'Global ⌘K overlay with grouped results, keyboard navigation, and AI entry transition.',
  label: 'Hero overlay',
  propsHint: '⌘K or trigger · Esc closes',
  trigger: 'Open command bar',
  hintPrefix: 'Press',
  hintSuffix: 'anywhere in the showcase.',
);

const _copyAr = _CommandBarCopy(
  description: 'تراكب ⌘K عام مع نتائج مجمّعة وتنقل بلوحة المفاتيح وانتقال إلى وضع الذكاء الاصطناعي.',
  label: 'Hero overlay',
  propsHint: '⌘K or trigger · Esc closes',
  trigger: 'افتح شريط الأوامر',
  hintPrefix: 'اضغط',
  hintSuffix: 'في أي مكان داخل العرض.',
);

_CommandBarCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Command bar showcase (web `CommandBarShowcase`).
class CommandBarShowcaseSection extends ConsumerWidget {
  const CommandBarShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'command-bar',
      title: 'Command bar',
      description: copy.description,
      componentName: 'CommandBar',
      child: ShowcaseDemo(
        label: copy.label,
        propsHint: copy.propsHint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              onPressed: () => ref.read(commandBarProvider.notifier).openCommandBar(),
              child: Text(copy.trigger),
            ),
            const SizedBox(height: AppSpacing.space2),
            Row(
              children: [
                Text(copy.hintPrefix, style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary)),
                const SizedBox(width: AppSpacing.space1),
                const AppKbd(keys: ['⌘', 'K']),
                const SizedBox(width: AppSpacing.space1),
                Text(copy.hintSuffix, style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
