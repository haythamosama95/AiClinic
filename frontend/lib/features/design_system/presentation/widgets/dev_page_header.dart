import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/dev_text_styles.dart';

/// Page header with title, description, and optional tabs (web `PageHeader`).
class DevPageHeader extends StatelessWidget {
  const DevPageHeader({required this.title, this.description, this.tabs, super.key});

  final String title;
  final String? description;
  final Widget? tabs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: DevTextStyles.h1(context)),
        if (description != null) ...[
          const SizedBox(height: AppSpacing.space1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 672),
            child: Text(
              description!,
              style: AppTypography.body(context).copyWith(color: context.appColors.textSecondary),
            ),
          ),
        ],
        if (tabs != null) ...[const SizedBox(height: AppSpacing.space4), tabs!],
      ],
    );
  }
}
