import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Surface or token color preview matching web `Swatch`.
class FoundationColorSwatch extends StatelessWidget {
  const FoundationColorSwatch({
    required this.label,
    required this.color,
    this.boxShadow,
    super.key,
  });

  final String label;
  final Color color;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: colors.borderSubtle),
            boxShadow: boxShadow,
          ),
          child: const SizedBox(height: 56, width: double.infinity),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(label, style: AppTypography.caption(context)),
      ],
    );
  }
}
