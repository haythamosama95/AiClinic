import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Rounded icon-chip + title header for invoice detail raised cards.
class InvoiceSectionTitle extends StatelessWidget {
  const InvoiceSectionTitle({
    required this.icon,
    required this.title,
    super.key,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceSelected,
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 18, color: colors.textLink),
          ),
        ),
        const SizedBox(width: AppSpacing.space3),
        Text(title, style: AppTypography.bodyStrong(context)),
      ],
    );
  }
}
