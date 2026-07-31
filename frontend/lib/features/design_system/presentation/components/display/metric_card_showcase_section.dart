import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_chart.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _MetricCardCopy {
  const _MetricCardCopy({
    required this.revenueToday,
    required this.outstanding,
    required this.vsYesterday,
  });

  final String revenueToday;
  final String outstanding;
  final String vsYesterday;
}

const _copyEn = _MetricCardCopy(
  revenueToday: 'Revenue today',
  outstanding: 'Outstanding',
  vsYesterday: 'vs. yesterday',
);

const _copyAr = _MetricCardCopy(
  revenueToday: 'إيرادات اليوم',
  outstanding: 'المستحق',
  vsYesterday: 'مقارنة بالأمس',
);

_MetricCardCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Metric card showcase (web `MetricCardShowcase` in `DataDisplayShowcase.tsx`).
class MetricCardShowcaseSection extends ConsumerWidget {
  const MetricCardShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);
    final colors = context.appColors;

    return ShowcaseSection(
      id: 'metric-card',
      title: 'Metric card',
      componentName: 'MetricCard',
      child: ShowcaseDemoGrid(
        columns: 2,
        children: [
          AppMetricCard(
            label: copy.revenueToday,
            value: '12,450.00',
            delta: const MetricDelta(
              value: '+8.2%',
              direction: MetricDeltaDirection.up,
              positive: true,
            ),
            caption: copy.vsYesterday,
            sparkline: AppChartSparkline(
              data: const [4, 6, 5, 8, 7, 9, 12],
              color: colors.actionPrimary,
            ),
          ),
          AppMetricCard(
            label: copy.outstanding,
            value: '3,200.00',
            delta: const MetricDelta(
              value: '\u22122.1%',
              direction: MetricDeltaDirection.down,
              positive: true,
            ),
          ),
        ],
      ),
    );
  }
}
