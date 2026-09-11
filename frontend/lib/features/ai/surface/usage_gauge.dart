import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

const kAiUsageGaugeKey = Key('ai_usage_gauge');
const kAiUsageGaugeGateKey = Key('ai_usage_gauge_gate');
const kAiUsageGaugeUnreachableKey = Key('ai_usage_gauge_unreachable');

/// Simple consumed-versus-budget gauge (G3 §4.1; credits only).
class UsageGauge extends StatelessWidget {
  const UsageGauge({
    super.key,
    required this.creditsUsed,
    required this.creditBudget,
  });

  final int creditsUsed;
  final int creditBudget;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final progress = creditBudget > 0 ? (creditsUsed / creditBudget).clamp(0.0, 1.0) : 0.0;

    return Semantics(
      key: kAiUsageGaugeKey,
      label: 'Credits used $creditsUsed of $creditBudget',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'AI credits',
            style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$creditsUsed',
                style: AppTypography.body(context).copyWith(color: colors.textPrimary),
              ),
              Text(
                '$creditBudget',
                style: AppTypography.body(context).copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Hidden gauge gate marker for non-enrolled installs (no network probe).
class UsageGaugeGate extends StatelessWidget {
  const UsageGaugeGate({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink(key: kAiUsageGaugeGateKey);
  }
}

/// Unreachable-state marker composed with E4 degraded view.
class UsageGaugeUnreachableMarker extends StatelessWidget {
  const UsageGaugeUnreachableMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink(key: kAiUsageGaugeUnreachableKey);
  }
}
