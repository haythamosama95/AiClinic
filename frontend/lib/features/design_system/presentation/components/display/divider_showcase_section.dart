import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_divider.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _DividerCopy {
  const _DividerCopy({
    required this.sectionDescription,
    required this.horizontal,
    required this.withLabel,
    required this.vertical,
    required this.sectionAbove,
    required this.sectionBelow,
    required this.orContinueWith,
    required this.patients,
    required this.appointments,
  });

  final String sectionDescription;
  final String horizontal;
  final String withLabel;
  final String vertical;
  final String sectionAbove;
  final String sectionBelow;
  final String orContinueWith;
  final String patients;
  final String appointments;
}

const _copyEn = _DividerCopy(
  sectionDescription: 'Hairline separators with optional centered label.',
  horizontal: 'Horizontal',
  withLabel: 'With label',
  vertical: 'Vertical',
  sectionAbove: 'Section above',
  sectionBelow: 'Section below',
  orContinueWith: 'Or continue with',
  patients: 'Patients',
  appointments: 'Appointments',
);

const _copyAr = _DividerCopy(
  sectionDescription: 'فواصل رفيعة مع تسمية اختيارية في المنتصف.',
  horizontal: 'أفقي',
  withLabel: 'مع تسمية',
  vertical: 'عمودي',
  sectionAbove: 'القسم أعلاه',
  sectionBelow: 'القسم أدناه',
  orContinueWith: 'أو المتابعة باستخدام',
  patients: 'المرضى',
  appointments: 'المواعيد',
);

_DividerCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Divider showcase (web `DividerShowcase`).
class DividerShowcaseSection extends ConsumerWidget {
  const DividerShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;
    final secondaryText = AppTypography.body(context).copyWith(color: colors.textSecondary);
    final bodySmText = AppTypography.bodySm(context).copyWith(color: colors.textSecondary);

    return ShowcaseSection(
      id: 'divider',
      title: 'Divider',
      description: copy.sectionDescription,
      componentName: 'Divider',
      child: ShowcaseDemoGrid(
        children: [
          ShowcaseDemo(
            label: copy.horizontal,
            propsHint: 'orientation="horizontal"',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(copy.sectionAbove, style: secondaryText),
                const SizedBox(height: AppSpacing.space4),
                const AppDivider(),
                const SizedBox(height: AppSpacing.space4),
                Text(copy.sectionBelow, style: secondaryText),
              ],
            ),
          ),
          ShowcaseDemo(
            label: copy.withLabel,
            propsHint: 'label',
            child: AppDivider(label: copy.orContinueWith),
          ),
          ShowcaseDemo(
            label: copy.vertical,
            propsHint: 'orientation="vertical"',
            child: SizedBox(
              height: 48,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(copy.patients, style: bodySmText),
                  const SizedBox(width: AppSpacing.space4),
                  const AppDivider(orientation: DividerOrientation.vertical),
                  const SizedBox(width: AppSpacing.space4),
                  Text(copy.appointments, style: bodySmText),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
