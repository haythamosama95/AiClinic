import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_signal.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// AI thinking pulse with label (web `ThinkingIndicator`).
class AppThinkingIndicator extends StatelessWidget {
  const AppThinkingIndicator({
    this.label = 'Thinking…',
    super.key,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      liveRegion: true,
      label: label,
      child: Row(
        children: [
          const SizedBox(
            width: 64,
            child: AppSignal(
              variant: AppSignalVariant.ai,
              orientation: Axis.horizontal,
              thinking: true,
            ),
          ),
          const SizedBox(width: AppSpacing.space3),
          Text(
            label,
            style: AppTypography.bodySm(context).copyWith(color: colors.textAi),
          ),
        ],
      ),
    );
  }
}
