import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Steady-state AI thinking affordance — Signal pulse plus optional label.
class AppAiThinkingIndicator extends StatelessWidget {
  const AppAiThinkingIndicator({
    this.label = 'Thinking…',
    super.key,
  });

  /// Status text shown beside the Signal pulse.
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: Row(
        children: [
          SizedBox(
            width: AppSpacing.s16,
            child: const AppSignalLine(
              ai: true,
              orientation: AppSignalOrientation.horizontal,
              thinking: true,
              length: AppSpacing.s16,
            ),
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Text(
              label,
              style: typography.bodySm.copyWith(color: colors.textAi),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
