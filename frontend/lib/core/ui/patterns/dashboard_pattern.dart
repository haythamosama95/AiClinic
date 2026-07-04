import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

import 'pattern_scaffold.dart';

/// Chart region inside [DashboardPattern].
class DashboardChartSlot {
  const DashboardChartSlot({
    required this.title,
    required this.chart,
    this.description,
    this.actions,
  });

  final String title;
  final String? description;
  final Widget chart;
  final Widget? actions;
}

/// Detail table region inside [DashboardPattern].
class DashboardTableSlot {
  const DashboardTableSlot({
    required this.title,
    required this.table,
    this.description,
    this.footer,
    this.actions,
  });

  final String title;
  final String? description;
  final Widget table;
  final Widget? footer;
  final Widget? actions;
}

/// Dashboard / analytics page scaffold — metrics, charts, and detail tables.
///
/// Composes [AppPageHeader] → metric row → charts grid → detail [AppTable]
/// slots. Callers supply [AppMetricCard], [AppChart], and [AppTable] widgets.
class DashboardPattern extends StatelessWidget {
  const DashboardPattern({
    required this.title,
    required this.metrics,
    this.description,
    this.breadcrumb,
    this.actions,
    this.charts = const [],
    this.tables = const [],
    super.key,
  });

  final String title;
  final String? description;
  final Widget? breadcrumb;
  final Widget? actions;
  final List<Widget> metrics;
  final List<DashboardChartSlot> charts;
  final List<DashboardTableSlot> tables;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = PatternScaffold.pagePadding(constraints.maxWidth);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AppScrollArea(
                child: Padding(
                  padding: padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppPageHeader(
                        title: title,
                        description: description,
                        breadcrumb: breadcrumb,
                        actions: actions,
                      ),
                      if (metrics.isNotEmpty) ...[
                        const SizedBox(height: PatternScaffold.sectionGap),
                        PatternResponsiveGrid(
                          columnCountForWidth: PatternScaffold.metricColumns,
                          children: metrics,
                        ),
                      ],
                      if (charts.isNotEmpty) ...[
                        const SizedBox(height: PatternScaffold.sectionGap),
                        PatternResponsiveGrid(
                          gap: AppSpacing.s6,
                          columnCountForWidth: PatternScaffold.chartColumns,
                          children: [
                            for (final slot in charts) _DashboardChartCard(slot: slot),
                          ],
                        ),
                      ],
                      if (tables.isNotEmpty) ...[
                        const SizedBox(height: PatternScaffold.sectionGap),
                        for (var i = 0; i < tables.length; i++) ...[
                          if (i > 0) const SizedBox(height: PatternScaffold.sectionGap),
                          _DashboardTableSection(slot: tables[i]),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashboardChartCard extends StatelessWidget {
  const _DashboardChartCard({required this.slot});

  final DashboardChartSlot slot;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        border: Border.all(color: colors.borderDefault),
        borderRadius: AppRadii.lgAll,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionHeader(
              title: slot.title,
              description: slot.description,
              actions: slot.actions,
            ),
            const SizedBox(height: AppSpacing.s4),
            slot.chart,
          ],
        ),
      ),
    );
  }
}

class _DashboardTableSection extends StatelessWidget {
  const _DashboardTableSection({required this.slot});

  final DashboardTableSlot slot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: slot.title,
          description: slot.description,
          actions: slot.actions,
        ),
        const SizedBox(height: AppSpacing.s4),
        slot.table,
        if (slot.footer != null) ...[
          const SizedBox(height: AppSpacing.s3),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: slot.footer!,
          ),
        ],
      ],
    );
  }
}
