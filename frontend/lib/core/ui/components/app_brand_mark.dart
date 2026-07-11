import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// AiClinic wordmark with stethoscope glyph (web `AiClinicMark`).
class AppBrandMark extends StatelessWidget {
  const AppBrandMark({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final squareSize = compact ? 32.0 : 36.0;
    final iconSize = compact ? 16.0 : 18.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          excludeSemantics: true,
          child: Container(
            width: squareSize,
            height: squareSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.actionPrimary,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Icon(Icons.medical_services_outlined, size: iconSize, color: colors.actionPrimaryFg),
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: AppSpacing.space2),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Ai',
                  style: AppTypography.h3(context).copyWith(color: colors.textPrimary),
                ),
                TextSpan(
                  text: 'Clinic',
                  style: AppTypography.h3(context).copyWith(color: colors.textLink),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
