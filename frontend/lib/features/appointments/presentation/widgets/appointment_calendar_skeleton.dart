import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';

/// Placeholder calendar grid shown while appointment data is loading.
class AppointmentCalendarSkeleton extends StatelessWidget {
  const AppointmentCalendarSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Skeletonizer(
      effect: ShimmerEffect(baseColor: colors.muted, highlightColor: colors.muted.withValues(alpha: 0.55)),
      containersColor: colors.muted,
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: SpacingTokens.xs),
                  const Expanded(
                    child: Column(
                      children: [
                        Text('Mon'),
                        SizedBox(height: SpacingTokens.xs),
                        Text('16'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: SpacingTokens.md),
            const Expanded(child: _CalendarGridSkeleton()),
          ],
        ),
      ),
    );
  }
}

class _CalendarGridSkeleton extends StatelessWidget {
  const _CalendarGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 44,
          child: Column(
            children: [
              for (var hour = 8; hour < 18; hour++) ...[
                if (hour > 8) const Spacer(),
                Text('${hour.toString().padLeft(2, '0')}:00'),
              ],
            ],
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: Column(
            children: [
              for (var row = 0; row < 6; row++) ...[
                if (row > 0) const SizedBox(height: SpacingTokens.sm),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var col = 0; col < 7; col++) ...[
                        if (col > 0) const SizedBox(width: SpacingTokens.xs),
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(border: Border.all(color: Colors.transparent)),
                            child: col.isEven && row.isOdd
                                ? Align(
                                    alignment: Alignment.topCenter,
                                    child: Container(
                                      height: 36,
                                      margin: const EdgeInsets.only(top: SpacingTokens.xs),
                                      decoration: BoxDecoration(
                                        color: Colors.blue,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
                                      child: const Text('Patient name'),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
