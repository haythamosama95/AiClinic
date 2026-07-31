import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_menu.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _MenuCopy {
  const _MenuCopy({
    required this.description,
    required this.dropdownLabel,
    required this.dropdownHint,
    required this.contextLabel,
    required this.contextHint,
    required this.openMenu,
    required this.rightClickHere,
    required this.patientSection,
    required this.editProfile,
    required this.copyMrn,
    required this.deleteRecord,
  });

  final String description;
  final String dropdownLabel;
  final String dropdownHint;
  final String contextLabel;
  final String contextHint;
  final String openMenu;
  final String rightClickHere;
  final String patientSection;
  final String editProfile;
  final String copyMrn;
  final String deleteRecord;
}

const _copyEn = _MenuCopy(
  description: 'Dropdown and right-click menus with icons, shortcuts, and destructive items.',
  dropdownLabel: 'Dropdown menu',
  dropdownHint: 'Menu + entries',
  contextLabel: 'Context menu',
  contextHint: 'right-click target',
  openMenu: 'Open menu',
  rightClickHere: 'Right-click here',
  patientSection: 'Patient',
  editProfile: 'Edit profile',
  copyMrn: 'Copy MRN',
  deleteRecord: 'Delete record',
);

const _copyAr = _MenuCopy(
  description: 'قوائم منسدلة وقوائم النقر بزر الفأرة الأيمن مع أيقونات واختصارات وعناصر مدمرة.',
  dropdownLabel: 'قائمة منسدلة',
  dropdownHint: 'Menu + entries',
  contextLabel: 'قائمة سياقية',
  contextHint: 'right-click target',
  openMenu: 'افتح القائمة',
  rightClickHere: 'انقر بزر الفأرة الأيمن هنا',
  patientSection: 'المريض',
  editProfile: 'تعديل الملف الشخصي',
  copyMrn: 'نسخ رقم السجل الطبي',
  deleteRecord: 'حذف السجل',
);

_MenuCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

List<AppMenuEntry> _menuEntries(_MenuCopy copy) => [
  AppMenuSection(
    label: copy.patientSection,
    items: [
      AppMenuItem(
        id: 'edit',
        label: copy.editProfile,
        icon: const Icon(Icons.edit_outlined, size: 16),
        shortcut: const ['⌘', 'E'],
        onSelect: () {},
      ),
      AppMenuItem(
        id: 'copy',
        label: copy.copyMrn,
        icon: const Icon(Icons.copy_outlined, size: 16),
        onSelect: () {},
      ),
    ],
  ),
  const AppMenuSeparator(),
  AppMenuItem(
    id: 'delete',
    label: copy.deleteRecord,
    icon: const Icon(Icons.delete_outline, size: 16),
    destructive: true,
    onSelect: () {},
  ),
];

/// Menu / Context menu showcase (web `MenuShowcase`).
class MenuShowcaseSection extends ConsumerWidget {
  const MenuShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final entries = _menuEntries(copy);
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'menu',
      title: 'Menu / Context menu',
      description: copy.description,
      componentName: 'Menu',
      child: ShowcaseDemoGrid(
        columns: 2,
        children: [
          ShowcaseDemo(
            label: copy.dropdownLabel,
            propsHint: copy.dropdownHint,
            child: AppMenu(
              entries: entries,
              trigger: AppButton(
                variant: AppButtonVariant.secondary,
                child: Text(copy.openMenu),
              ),
            ),
          ),
          ShowcaseDemo(
            label: copy.contextLabel,
            propsHint: copy.contextHint,
            child: AppContextMenu(
              entries: entries,
              child: CustomPaint(
                painter: _DashedBorderPainter(
                  color: colors.borderDefault,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space8,
                    vertical: AppSpacing.space6,
                  ),
                  child: Text(
                    copy.rightClickHere,
                    style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.borderRadius});

  final Color color;
  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    const dashWidth = 5.0;
    const dashSpace = 4.0;
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, end.clamp(0, metric.length)), paint);
        distance = end + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.borderRadius != borderRadius;
  }
}
