import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Sub-section header with optional description and actions slots (web `SectionHeader`).
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    required this.title,
    this.description,
    this.actions,
    super.key,
  });

  final String title;
  final String? description;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.overline(context).copyWith(color: colors.textTertiary),
              ),
              if (description != null) ...[
                const SizedBox(height: AppSpacing.space1),
                Text(
                  description!,
                  style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        if (actions != null)
          Wrap(
            spacing: AppSpacing.space2,
            runSpacing: AppSpacing.space2,
            children: [actions!],
          ),
      ],
    );
  }
}
