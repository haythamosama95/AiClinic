import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_resizable_panels.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _ResizablePanelsLayoutCopy {
  const _ResizablePanelsLayoutCopy({
    required this.patientList,
    required this.patientDetail,
  });

  final String patientList;
  final String patientDetail;
}

const _copyEn = _ResizablePanelsLayoutCopy(
  patientList: 'Patient list',
  patientDetail: 'Patient detail',
);

const _copyAr = _ResizablePanelsLayoutCopy(
  patientList: 'قائمة المرضى',
  patientDetail: 'تفاصيل المريض',
);

_ResizablePanelsLayoutCopy _copyFor(String locale) =>
    locale == 'ar' ? _copyAr : _copyEn;

/// Layout-group resizable panels showcase (web `ResizablePanelsLayoutShowcase`).
class ResizablePanelsLayoutShowcaseSection extends ConsumerWidget {
  const ResizablePanelsLayoutShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final paneStyle = AppTypography.bodySm(context);

    return ShowcaseSection(
      id: 'layout-resizable',
      title: 'Resizable panels',
      componentName: 'ResizablePanels',
      child: AppResizablePanels(
        start: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: Text(copy.patientList, style: paneStyle),
        ),
        end: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: Text(copy.patientDetail, style: paneStyle),
        ),
      ),
    );
  }
}
