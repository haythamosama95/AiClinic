import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_drawer.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _DrawerCopy {
  const _DrawerCopy({
    required this.openDrawer,
    required this.title,
    required this.description,
    required this.close,
    required this.body,
  });

  final String openDrawer;
  final String title;
  final String description;
  final String close;
  final String body;
}

const _copyEn = _DrawerCopy(
  openDrawer: 'Open drawer',
  title: 'Patient detail',
  description: 'Side panel without leaving context',
  close: 'Close',
  body: 'Detail content for patient Layla Hassan.',
);

const _copyAr = _DrawerCopy(
  openDrawer: 'فتح اللوحة الجانبية',
  title: 'تفاصيل المريض',
  description: 'لوحة جانبية دون مغادرة السياق',
  close: 'إغلاق',
  body: 'محتوى تفصيلي للمريض ليلى حسن.',
);

_DrawerCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Drawer showcase (web `DrawerShowcase`).
class DrawerShowcaseSection extends ConsumerStatefulWidget {
  const DrawerShowcaseSection({super.key});

  @override
  ConsumerState<DrawerShowcaseSection> createState() => _DrawerShowcaseSectionState();
}

class _DrawerShowcaseSectionState extends ConsumerState<DrawerShowcaseSection> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'drawer',
      title: 'Drawer / Sheet',
      componentName: 'Drawer',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppButton(
            onPressed: () => setState(() => _open = true),
            child: Text(copy.openDrawer),
          ),
          AppDrawer(
            open: _open,
            onOpenChange: (open) => setState(() => _open = open),
            title: copy.title,
            description: copy.description,
            footer: Builder(
              builder: (dialogContext) => AppButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(copy.close),
              ),
            ),
            children: [
              Text(
                copy.body,
                style: AppTypography.body(context).copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
