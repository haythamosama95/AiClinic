import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_kbd.dart';
import 'package:ai_clinic/core/ui/components/app_tooltip.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _TooltipCopy {
  const _TooltipCopy({
    required this.sectionDescription,
    required this.defaultLabel,
    required this.defaultHint,
    required this.shortcutLabel,
    required this.shortcutHint,
    required this.placementLabel,
    required this.placementHint,
    required this.defaultTrigger,
    required this.defaultContent,
    required this.shortcutTrigger,
    required this.shortcutPrefix,
    required this.placementTop,
    required this.placementRight,
    required this.placementBottom,
    required this.placementLeft,
  });

  final String sectionDescription;
  final String defaultLabel;
  final String defaultHint;
  final String shortcutLabel;
  final String shortcutHint;
  final String placementLabel;
  final String placementHint;
  final String defaultTrigger;
  final String defaultContent;
  final String shortcutTrigger;
  final String shortcutPrefix;
  final String placementTop;
  final String placementRight;
  final String placementBottom;
  final String placementLeft;

  String placementFor(TooltipSide side) => switch (side) {
    TooltipSide.top => placementTop,
    TooltipSide.right => placementRight,
    TooltipSide.bottom => placementBottom,
    TooltipSide.left => placementLeft,
  };
}

const _copyEn = _TooltipCopy(
  sectionDescription: 'Brief supplementary text on hover or focus. Never holds essential-only information.',
  defaultLabel: 'Default',
  defaultHint: 'delay 400ms',
  shortcutLabel: 'With shortcut hint',
  shortcutHint: 'pairs with Kbd',
  placementLabel: 'Placement',
  placementHint: 'side="top|bottom|left|right"',
  defaultTrigger: 'Hover or focus me',
  defaultContent: 'View patient history',
  shortcutTrigger: 'Quick actions',
  shortcutPrefix: 'Open Command Bar',
  placementTop: 'Tooltip on top',
  placementRight: 'Tooltip on right',
  placementBottom: 'Tooltip on bottom',
  placementLeft: 'Tooltip on left',
);

const _copyAr = _TooltipCopy(
  sectionDescription: 'نص تكميلي موجز عند التمرير أو التركيز. لا يحتوي أبدًا على معلومات أساسية فقط.',
  defaultLabel: 'افتراضي',
  defaultHint: 'delay 400ms',
  shortcutLabel: 'مع تلميح اختصار',
  shortcutHint: 'pairs with Kbd',
  placementLabel: 'الموضع',
  placementHint: 'side="top|bottom|left|right"',
  defaultTrigger: 'مرّر أو ركّز هنا',
  defaultContent: 'عرض سجل المريض',
  shortcutTrigger: 'إجراءات سريعة',
  shortcutPrefix: 'فتح شريط الأوامر',
  placementTop: 'تلميح أعلى',
  placementRight: 'تلميح يمين',
  placementBottom: 'تلميح أسفل',
  placementLeft: 'تلميح يسار',
);

_TooltipCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Tooltip showcase (web `TooltipShowcase`).
class TooltipShowcaseSection extends ConsumerWidget {
  const TooltipShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'tooltip',
      title: 'Tooltip',
      description: copy.sectionDescription,
      componentName: 'Tooltip',
      child: ShowcaseDemoGrid(
        children: [
          ShowcaseDemo(
            label: copy.defaultLabel,
            propsHint: copy.defaultHint,
            child: AppTooltip(
              message: copy.defaultContent,
              child: _BorderedTooltipTrigger(
                onPressed: () {},
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: colors.iconDefault),
                    const SizedBox(width: AppSpacing.space2),
                    Text(copy.defaultTrigger, style: AppTypography.bodyStrong(context)),
                  ],
                ),
              ),
            ),
          ),
          ShowcaseDemo(
            label: copy.shortcutLabel,
            propsHint: copy.shortcutHint,
            child: AppTooltip(
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(copy.shortcutPrefix),
                  const SizedBox(width: AppSpacing.space2),
                  const AppKbd(keys: ['⌘', 'K']),
                ],
              ),
              child: AppButton(onPressed: () {}, child: Text(copy.shortcutTrigger)),
            ),
          ),
          ShowcaseDemo(
            label: copy.placementLabel,
            propsHint: copy.placementHint,
            child: Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              children: [
                for (final side in TooltipSide.values)
                  AppTooltip(
                    side: side,
                    content: Text(copy.placementFor(side)),
                    child: _BorderedTooltipTrigger(
                      onPressed: () {},
                      child: Text(side.name, style: AppTypography.body(context).copyWith(color: colors.textSecondary)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BorderedTooltipTrigger extends StatelessWidget {
  const _BorderedTooltipTrigger({required this.onPressed, required this.child});

  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.md),
        hoverColor: colors.surfaceHover,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colors.borderDefault),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
            child: child,
          ),
        ),
      ),
    );
  }
}
