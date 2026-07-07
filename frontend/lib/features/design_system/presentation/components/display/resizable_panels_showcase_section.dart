import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_resizable_panels.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _ResizablePanelsCopy {
  const _ResizablePanelsCopy({
    required this.masterListPane,
    required this.detailPane,
  });

  final String masterListPane;
  final String detailPane;
}

const _copyEn = _ResizablePanelsCopy(
  masterListPane: 'Master list pane',
  detailPane: 'Detail pane — drag the divider or use arrow keys',
);

const _copyAr = _ResizablePanelsCopy(
  masterListPane: 'لوحة القائمة الرئيسية',
  detailPane: 'لوحة التفاصيل — اسحب الفاصل أو استخدم مفاتيح الأسهم',
);

_ResizablePanelsCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Resizable panels showcase (web `ResizablePanelsShowcase`).
class ResizablePanelsShowcaseSection extends ConsumerWidget {
  const ResizablePanelsShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final paneStyle = AppTypography.bodySm(context);

    return ShowcaseSection(
      id: 'resizable-panels',
      title: 'Resizable panels',
      componentName: 'ResizablePanels',
      child: AppResizablePanels(
        start: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: Text(copy.masterListPane, style: paneStyle),
        ),
        end: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: Text(copy.detailPane, style: paneStyle),
        ),
      ),
    );
  }
}
