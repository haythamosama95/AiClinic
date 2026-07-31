import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_scroll_area.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _ScrollAreaCopy {
  const _ScrollAreaCopy({required this.scrollableRow});

  final String Function(int index) scrollableRow;
}

final _copyEn = _ScrollAreaCopy(
  scrollableRow: (index) => 'Scrollable row $index',
);

final _copyAr = _ScrollAreaCopy(
  scrollableRow: (index) => 'صف قابل للتمرير $index',
);

_ScrollAreaCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Scroll area showcase (web `ScrollAreaShowcase`).
class ScrollAreaShowcaseSection extends ConsumerWidget {
  const ScrollAreaShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'scroll-area',
      title: 'Scroll area',
      componentName: 'ScrollArea',
      child: AppScrollArea(
        maxHeight: 160,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.space2,
            children: [
              for (var i = 0; i < 12; i++)
                Text(
                  copy.scrollableRow(i + 1),
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
