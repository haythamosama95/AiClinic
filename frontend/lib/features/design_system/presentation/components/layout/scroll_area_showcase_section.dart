import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_scroll_area.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _LayoutScrollAreaCopy {
  const _LayoutScrollAreaCopy({required this.scrollItem});

  final String Function(int index) scrollItem;
}

final _copyEn = _LayoutScrollAreaCopy(
  scrollItem: (index) => 'Layout scroll item $index',
);

final _copyAr = _LayoutScrollAreaCopy(
  scrollItem: (index) => 'عنصر تمرير التخطيط $index',
);

_LayoutScrollAreaCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Layout-group scroll area showcase (web `ScrollAreaLayoutShowcase`).
class LayoutScrollAreaShowcaseSection extends ConsumerWidget {
  const LayoutScrollAreaShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'layout-scroll-area',
      title: 'Scroll area',
      componentName: 'ScrollArea',
      child: AppScrollArea(
        maxHeight: 120,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.space2,
            children: [
              for (var i = 0; i < 8; i++)
                Text(
                  copy.scrollItem(i + 1),
                  style: AppTypography.bodySm(context).copyWith(
                    color: colors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
