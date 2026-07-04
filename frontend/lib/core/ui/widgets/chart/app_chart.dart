import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/data/app_description_list.dart';
import 'package:ai_clinic/core/ui/widgets/data/app_table.dart';
import 'package:ai_clinic/core/ui/widgets/feedback/app_empty_state.dart';

/// Supported chart visualizations in [AppChart].
enum AppChartType {
  line,
  area,
  bar,
  stackedBar,
  donut,
  sparkline,
}

/// A single data point for [AppChartSeries].
///
/// [x] defaults to the point index when omitted. [xLabel] is used for
/// categorical axis labels and accessible summaries.
@immutable
class AppChartPoint {
  const AppChartPoint({
    required this.y,
    this.x,
    this.xLabel,
  });

  final double y;
  final double? x;
  final String? xLabel;
}

/// Named series of [AppChartPoint] values shared across chart types.
@immutable
class AppChartSeries {
  const AppChartSeries({
    required this.name,
    required this.points,
    this.color,
  });

  final String name;
  final List<AppChartPoint> points;
  final Color? color;
}

/// Axis display options for Cartesian [AppChart] variants.
@immutable
class AppChartAxisConfig {
  const AppChartAxisConfig({
    this.showXAxis = true,
    this.showYAxis = true,
    this.yMin,
    this.yMax,
    this.xAxisLabel,
    this.yAxisLabel,
  });

  final bool showXAxis;
  final bool showYAxis;
  final double? yMin;
  final double? yMax;
  final String? xAxisLabel;
  final String? yAxisLabel;
}

/// Categorical series palette derived from design tokens:
/// teal primary, info/success/warning status hues, tertiary neutral, AI violet.
///
/// Mirrors the web `chartPalette` mapping to semantic tokens.
List<Color> appChartPalette(AppColors colors) => [
      colors.actionPrimary,
      colors.statusInfoFg,
      colors.statusSuccessFg,
      colors.statusWarningFg,
      colors.textTertiary,
      colors.actionAi,
    ];

/// Lightweight inline trend line for metric cards and compact summaries.
///
/// Implemented with [CustomPainter] — no axes, grid, or tooltips.
class AppChartSparkline extends StatelessWidget {
  const AppChartSparkline({
    required this.data,
    this.color,
    this.width = AppSpacing.s20,
    this.height = AppSpacing.s6,
    super.key,
  });

  /// Numeric values plotted left-to-right.
  final List<double> data;

  final Color? color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(width: width, height: height);
    }

    final colors = context.colors;
    final strokeColor = color ?? appChartPalette(colors).first;

    return Semantics(
      label: _sparklineSemanticsLabel(data),
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            painter: _SparklinePainter(
              data: data,
              color: strokeColor,
              strokeWidth: AppSpacing.sPx + AppSpacing.s0_5 / 2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Token-styled chart wrapper over `fl_chart` with accessible fallbacks.
class AppChart extends ConsumerStatefulWidget {
  const AppChart({
    required this.type,
    required this.series,
    this.title,
    this.axisConfig = const AppChartAxisConfig(),
    this.showLegend = true,
    this.showDataTableFallback = false,
    this.height = AppSpacing.s20 * 2 + AppSpacing.s10,
    this.semanticsLabel,
    super.key,
  });

  final AppChartType type;
  final List<AppChartSeries> series;
  final String? title;
  final AppChartAxisConfig axisConfig;
  final bool showLegend;
  final bool showDataTableFallback;
  final double height;
  final String? semanticsLabel;

  @override
  ConsumerState<AppChart> createState() => _AppChartState();
}

class _AppChartState extends ConsumerState<AppChart> {
  int? _touchedDonutIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.type == AppChartType.sparkline) {
      final first = widget.series.firstOrNull;
      if (first == null || first.points.isEmpty) {
        return const SizedBox.shrink();
      }
      return AppChartSparkline(
        data: first.points.map((p) => p.y).toList(),
        color: first.color,
      );
    }

    if (!_hasChartData(widget.series, widget.type)) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noResults,
        title: 'No chart data',
        description: 'There is nothing to display yet.',
      );
    }

    final semanticsLabel =
        widget.semanticsLabel ?? _buildSemanticsLabel(widget.series, widget.type);

    return Semantics(
      label: semanticsLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChartFrame(
            title: widget.title,
            child: _buildChart(context),
          ),
          if (widget.showLegend && _supportsLegend(widget.type)) ...[
            const SizedBox(height: AppSpacing.s2),
            _ChartLegend(series: widget.series),
          ],
          if (widget.showDataTableFallback) ...[
            const SizedBox(height: AppSpacing.s4),
            _ChartDataFallback(
              type: widget.type,
              series: widget.series,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context) {
    final reduced = ref.watch(reducedMotionProvider) ||
        AppMotion.reduced(context);
    final duration =
        reduced ? Duration.zero : AppDurations.base;
    final curve = AppEasings.standard;

    return switch (widget.type) {
      AppChartType.line ||
      AppChartType.area =>
        _LineChartBody(
          series: widget.series,
          height: widget.height,
          axisConfig: widget.axisConfig,
          filled: widget.type == AppChartType.area,
          duration: duration,
          curve: curve,
        ),
      AppChartType.bar => _BarChartBody(
          series: widget.series,
          height: widget.height,
          axisConfig: widget.axisConfig,
          stacked: false,
          duration: duration,
          curve: curve,
        ),
      AppChartType.stackedBar => _BarChartBody(
          series: widget.series,
          height: widget.height,
          axisConfig: widget.axisConfig,
          stacked: true,
          duration: duration,
          curve: curve,
        ),
      AppChartType.donut => _DonutChartBody(
          series: widget.series,
          height: widget.height,
          duration: duration,
          curve: curve,
          touchedIndex: _touchedDonutIndex,
          onSectionTouch: (index) {
            setState(() => _touchedDonutIndex = index);
          },
        ),
      AppChartType.sparkline => const SizedBox.shrink(),
    };
  }
}

class _ChartFrame extends StatelessWidget {
  const _ChartFrame({
    required this.child,
    this.title,
  });

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: colors.borderDefault),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: typography.title.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.s3),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _LineChartBody extends StatelessWidget {
  const _LineChartBody({
    required this.series,
    required this.height,
    required this.axisConfig,
    required this.filled,
    required this.duration,
    required this.curve,
  });

  final List<AppChartSeries> series;
  final double height;
  final AppChartAxisConfig axisConfig;
  final bool filled;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final palette = appChartPalette(colors);
    final pointCount = _maxPointCount(series);
    final yRange = _computeYRange(series, axisConfig.yMin, axisConfig.yMax);
    final xLabels = _resolveXLabels(series, pointCount);

    final lineBars = <LineChartBarData>[];
    for (var si = 0; si < series.length; si++) {
      final s = series[si];
      final color = s.color ?? palette[si % palette.length];
      final spots = _spotsForSeries(s, pointCount);

      lineBars.add(
        LineChartBarData(
          spots: spots,
          isCurved: false,
          color: color,
          barWidth: AppSpacing.s0_5,
          dotData: const FlDotData(show: true),
          belowBarData: filled
              ? BarAreaData(
                  show: true,
                  color: color.withValues(alpha: 0.12),
                )
              : BarAreaData(show: false),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: LineChart(
        _buildLineChartData(
          context: context,
          lineBars: lineBars,
          pointCount: pointCount,
          yRange: yRange,
          xLabels: xLabels,
          axisConfig: axisConfig,
          colors: colors,
          typography: typography,
        ),
        duration: duration,
        curve: curve,
      ),
    );
  }
}

class _BarChartBody extends StatelessWidget {
  const _BarChartBody({
    required this.series,
    required this.height,
    required this.axisConfig,
    required this.stacked,
    required this.duration,
    required this.curve,
  });

  final List<AppChartSeries> series;
  final double height;
  final AppChartAxisConfig axisConfig;
  final bool stacked;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final palette = appChartPalette(colors);
    final pointCount = _maxPointCount(series);
    final yRange = _computeYRange(
      series,
      axisConfig.yMin,
      axisConfig.yMax,
      stacked: stacked,
    );
    final xLabels = _resolveXLabels(series, pointCount);

    final groups = <BarChartGroupData>[];
    for (var i = 0; i < pointCount; i++) {
      if (stacked) {
        var stackBase = 0.0;
        final stackItems = <BarChartRodStackItem>[];
        for (var si = 0; si < series.length; si++) {
          final value = _pointY(series[si], i);
          final color = series[si].color ?? palette[si % palette.length];
          stackItems.add(
            BarChartRodStackItem(stackBase, stackBase + value, color),
          );
          stackBase += value;
        }
        groups.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: stackBase,
                rodStackItems: stackItems,
                width: AppSpacing.s4,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadii.sm),
                ),
              ),
            ],
          ),
        );
      } else {
        final rods = <BarChartRodData>[];
        for (var si = 0; si < series.length; si++) {
          final value = _pointY(series[si], i);
          final color = series[si].color ?? palette[si % palette.length];
          rods.add(
            BarChartRodData(
              toY: value,
              color: color,
              width: AppSpacing.s3,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadii.sm),
              ),
            ),
          );
        }
        groups.add(BarChartGroupData(x: i, barRods: rods));
      }
    }

    return SizedBox(
      height: height,
      child: BarChart(
        _buildBarChartData(
          context: context,
          groups: groups,
          pointCount: pointCount,
          yRange: yRange,
          xLabels: xLabels,
          axisConfig: axisConfig,
          series: series,
          colors: colors,
          typography: typography,
        ),
        duration: duration,
        curve: curve,
      ),
    );
  }
}

class _DonutChartBody extends StatelessWidget {
  const _DonutChartBody({
    required this.series,
    required this.height,
    required this.duration,
    required this.curve,
    required this.touchedIndex,
    required this.onSectionTouch,
  });

  final List<AppChartSeries> series;
  final double height;
  final Duration duration;
  final Curve curve;
  final int? touchedIndex;
  final ValueChanged<int?> onSectionTouch;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final palette = appChartPalette(colors);
    final slices = _donutSlices(series);

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < slices.length; i++) {
      final slice = slices[i];
      final isTouched = touchedIndex == i;
      sections.add(
        PieChartSectionData(
          value: slice.value,
          color: slice.color ?? palette[i % palette.length],
          radius: isTouched ? height / 2 - AppSpacing.s4 : height / 2 - AppSpacing.s4,
          title: '',
          showTitle: false,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: height,
          height: height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: height * 0.275,
                  centerSpaceColor: colors.surfaceDefault,
                  sectionsSpace: AppSpacing.s0_5,
                  startDegreeOffset: -90,
                  borderData: FlBorderData(show: false),
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (!event.isInterestedForInteractions) {
                        onSectionTouch(null);
                        return;
                      }
                      onSectionTouch(response?.touchedSection?.touchedSectionIndex);
                    },
                  ),
                ),
                duration: duration,
                curve: curve,
              ),
              if (touchedIndex != null && touchedIndex! < slices.length)
                _DonutTooltip(
                  label: slices[touchedIndex!].label,
                  value: slices[touchedIndex!].value,
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < slices.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s1),
                  child: Row(
                    children: [
                      Container(
                        width: AppSpacing.s2,
                        height: AppSpacing.s2,
                        decoration: BoxDecoration(
                          color: slices[i].color ?? palette[i % palette.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      Expanded(
                        child: Text(
                          slices[i].label,
                          style: typography.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        _formatWesternNumber(slices[i].value),
                        style: typography.tabular(typography.caption).copyWith(
                              color: colors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutTooltip extends StatelessWidget {
  const _DonutTooltip({
    required this.label,
    required this.value,
  });

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final brightness = Theme.of(context).brightness;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: colors.borderDefault),
        boxShadow: AppShadows.forLevel(2, brightness),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s2,
        ),
        child: Text(
          '$label: ${_formatWesternNumber(value)}',
          style: typography.tabular(typography.caption).copyWith(
                color: colors.textPrimary,
              ),
        ),
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.series});

  final List<AppChartSeries> series;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final palette = appChartPalette(colors);

    return Wrap(
      spacing: AppSpacing.s4,
      runSpacing: AppSpacing.s2,
      children: [
        for (var i = 0; i < series.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: AppSpacing.s2,
                height: AppSpacing.s2,
                decoration: BoxDecoration(
                  color: series[i].color ?? palette[i % palette.length],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.s1 + AppSpacing.s0_5),
              Text(
                series[i].name,
                style: typography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _ChartDataFallback extends StatelessWidget {
  const _ChartDataFallback({
    required this.type,
    required this.series,
  });

  final AppChartType type;
  final List<AppChartSeries> series;

  @override
  Widget build(BuildContext context) {
    if (type == AppChartType.donut) {
      final slices = _donutSlices(series);
      return AppDescriptionList(
        columns: 1,
        items: [
          for (final slice in slices)
            AppDescriptionItem(
              label: slice.label,
              value: Text(_formatWesternNumber(slice.value)),
              tabular: true,
            ),
        ],
      );
    }

    final pointCount = _maxPointCount(series);
    final xLabels = _resolveXLabels(series, pointCount);
    final rows = series
        .map(
          (s) => _ChartTableRow(
            seriesName: s.name,
            values: List.generate(
              pointCount,
              (i) => _formatWesternNumber(_pointY(s, i)),
            ),
          ),
        )
        .toList();

    final columns = <AppTableColumn<_ChartTableRow>>[
      AppTableColumn(
        id: 'series',
        header: 'Series',
        cellBuilder: (context, row) => Text(row.seriesName),
      ),
      ...List.generate(
        pointCount,
        (i) => AppTableColumn(
          id: 'x_$i',
          header: xLabels[i],
          align: AppTableColumnAlign.end,
          cellBuilder: (context, row) => Text(
            row.values[i],
            style: context.typography.tabular(context.typography.bodySm),
          ),
        ),
      ),
    ];

    return AppTable<_ChartTableRow>(
      columns: columns,
      rowId: (row) => row.seriesName,
      data: rows,
      density: AppTableDensity.compact,
    );
  }
}

@immutable
class _ChartTableRow {
  const _ChartTableRow({
    required this.seriesName,
    required this.values,
  });

  final String seriesName;
  final List<String> values;
}

@immutable
class _DonutSlice {
  const _DonutSlice({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final double value;
  final Color? color;
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.data,
    required this.color,
    required this.strokeWidth,
  });

  final List<double> data;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final padding = AppSpacing.s0_5.toDouble();
    final max = data.reduce(math.max);
    final min = data.reduce(math.min);
    final range = max - min == 0 ? 1.0 : max - min;
    final innerW = size.width - padding * 2;
    final innerH = size.height - padding * 2;

    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = padding + (i / math.max(data.length - 1, 1)) * innerW;
      final y = padding + innerH - ((data[i] - min) / range) * innerH;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

LineChartData _buildLineChartData({
  required BuildContext context,
  required List<LineChartBarData> lineBars,
  required int pointCount,
  required ({double min, double max}) yRange,
  required List<String> xLabels,
  required AppChartAxisConfig axisConfig,
  required AppColors colors,
  required AppTypography typography,
}) {
  final textDirection = Directionality.of(context);

  return LineChartData(
    lineBarsData: lineBars,
    minX: 0,
    maxX: math.max(pointCount - 1, 1).toDouble(),
    minY: yRange.min,
    maxY: yRange.max,
    gridData: FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: (yRange.max - yRange.min) / 4,
      getDrawingHorizontalLine: (value) => FlLine(
        color: colors.borderSubtle.withValues(alpha: 0.5),
        strokeWidth: AppSpacing.sPx.toDouble(),
      ),
      checkToShowHorizontalLine: (value) {
        final pct = (value - yRange.min) / (yRange.max - yRange.min);
        return (pct - 0.25).abs() < 0.05 ||
            (pct - 0.5).abs() < 0.05 ||
            (pct - 0.75).abs() < 0.05;
      },
    ),
    borderData: FlBorderData(show: false),
    titlesData: FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        axisNameWidget: axisConfig.yAxisLabel != null
            ? Text(
                axisConfig.yAxisLabel!,
                textDirection: textDirection,
                style: typography.caption.copyWith(color: colors.textTertiary),
              )
            : null,
        axisNameSize: axisConfig.yAxisLabel != null ? AppSpacing.s6 : 0,
        sideTitles: SideTitles(
          showTitles: axisConfig.showYAxis,
          reservedSize: AppSpacing.s8,
          getTitlesWidget: (value, meta) => _axisTitleWidget(
            context: context,
            value: value,
            typography: typography,
            colors: colors,
            textDirection: textDirection,
            meta: meta,
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        axisNameWidget: axisConfig.xAxisLabel != null
            ? Text(
                axisConfig.xAxisLabel!,
                textDirection: textDirection,
                style: typography.caption.copyWith(color: colors.textTertiary),
              )
            : null,
        axisNameSize: axisConfig.xAxisLabel != null ? AppSpacing.s6 : 0,
        sideTitles: SideTitles(
          showTitles: axisConfig.showXAxis,
          reservedSize: AppSpacing.s6,
          interval: 1,
          getTitlesWidget: (value, meta) {
            final index = value.round();
            if (index < 0 || index >= xLabels.length) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              meta: meta,
              child: Text(
                xLabels[index],
                textDirection: textDirection,
                style: typography.caption.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            );
          },
        ),
      ),
    ),
    lineTouchData: LineTouchData(
      enabled: true,
      handleBuiltInTouches: true,
      touchTooltipData: _lineTooltipData(
        context: context,
        colors: colors,
        typography: typography,
        series: lineBars,
        xLabels: xLabels,
      ),
    ),
  );
}

BarChartData _buildBarChartData({
  required BuildContext context,
  required List<BarChartGroupData> groups,
  required int pointCount,
  required ({double min, double max}) yRange,
  required List<String> xLabels,
  required AppChartAxisConfig axisConfig,
  required List<AppChartSeries> series,
  required AppColors colors,
  required AppTypography typography,
}) {
  final textDirection = Directionality.of(context);
  final palette = appChartPalette(colors);

  return BarChartData(
    barGroups: groups,
    minY: yRange.min,
    maxY: yRange.max,
    gridData: FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: (yRange.max - yRange.min) / 4,
      getDrawingHorizontalLine: (value) => FlLine(
        color: colors.borderSubtle.withValues(alpha: 0.5),
        strokeWidth: AppSpacing.sPx.toDouble(),
      ),
      checkToShowHorizontalLine: (value) {
        final pct = (value - yRange.min) / (yRange.max - yRange.min);
        return (pct - 0.25).abs() < 0.05 ||
            (pct - 0.5).abs() < 0.05 ||
            (pct - 0.75).abs() < 0.05;
      },
    ),
    borderData: FlBorderData(show: false),
    titlesData: FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        axisNameWidget: axisConfig.yAxisLabel != null
            ? Text(
                axisConfig.yAxisLabel!,
                textDirection: textDirection,
                style: typography.caption.copyWith(color: colors.textTertiary),
              )
            : null,
        axisNameSize: axisConfig.yAxisLabel != null ? AppSpacing.s6 : 0,
        sideTitles: SideTitles(
          showTitles: axisConfig.showYAxis,
          reservedSize: AppSpacing.s8,
          getTitlesWidget: (value, meta) => _axisTitleWidget(
            context: context,
            value: value,
            typography: typography,
            colors: colors,
            textDirection: textDirection,
            meta: meta,
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        axisNameWidget: axisConfig.xAxisLabel != null
            ? Text(
                axisConfig.xAxisLabel!,
                textDirection: textDirection,
                style: typography.caption.copyWith(color: colors.textTertiary),
              )
            : null,
        axisNameSize: axisConfig.xAxisLabel != null ? AppSpacing.s6 : 0,
        sideTitles: SideTitles(
          showTitles: axisConfig.showXAxis,
          reservedSize: AppSpacing.s6,
          interval: 1,
          getTitlesWidget: (value, meta) {
            final index = value.round();
            if (index < 0 || index >= xLabels.length) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              meta: meta,
              child: Text(
                xLabels[index],
                textDirection: textDirection,
                style: typography.caption.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            );
          },
        ),
      ),
    ),
    barTouchData: BarTouchData(
      enabled: true,
      handleBuiltInTouches: true,
      touchTooltipData: _barTooltipData(
        colors: colors,
        typography: typography,
        series: series,
        xLabels: xLabels,
        palette: palette,
      ),
    ),
  );
}

LineTouchTooltipData _lineTooltipData({
  required BuildContext context,
  required AppColors colors,
  required AppTypography typography,
  required List<LineChartBarData> series,
  required List<String> xLabels,
}) {
  return LineTouchTooltipData(
    tooltipBorderRadius: AppRadii.mdAll,
    tooltipPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s3,
      vertical: AppSpacing.s2,
    ),
    tooltipMargin: AppSpacing.s2,
    getTooltipColor: (_) => colors.surfaceRaised,
    tooltipBorder: BorderSide(color: colors.borderDefault),
    getTooltipItems: (spots) {
      return spots.map((spot) {
        final index = spot.x.round();
        final label = index >= 0 && index < xLabels.length
            ? xLabels[index]
            : _formatWesternNumber(spot.x);
        return LineTooltipItem(
          '$label\n${_formatWesternNumber(spot.y)}',
          typography.tabular(typography.caption).copyWith(
                color: colors.textPrimary,
              ),
        );
      }).toList();
    },
  );
}

BarTouchTooltipData _barTooltipData({
  required AppColors colors,
  required AppTypography typography,
  required List<AppChartSeries> series,
  required List<String> xLabels,
  required List<Color> palette,
}) {
  return BarTouchTooltipData(
    tooltipBorderRadius: AppRadii.mdAll,
    tooltipPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s3,
      vertical: AppSpacing.s2,
    ),
    tooltipMargin: AppSpacing.s2,
    getTooltipColor: (_) => colors.surfaceRaised,
    tooltipBorder: BorderSide(color: colors.borderDefault),
    getTooltipItem: (group, groupIndex, rod, rodIndex) {
      final xLabel = groupIndex >= 0 && groupIndex < xLabels.length
          ? xLabels[groupIndex]
          : '';
      final seriesName =
          rodIndex < series.length ? series[rodIndex].name : '';
      final value = rod.toY;
      return BarTooltipItem(
        '$seriesName\n$xLabel: ${_formatWesternNumber(value)}',
        typography.tabular(typography.caption).copyWith(
              color: colors.textPrimary,
            ),
      );
    },
  );
}

Widget _axisTitleWidget({
  required BuildContext context,
  required double value,
  required AppTypography typography,
  required AppColors colors,
  required TextDirection textDirection,
  required TitleMeta meta,
}) {
  if (meta.max == value || meta.min == value) {
    return const SizedBox.shrink();
  }

  return SideTitleWidget(
    meta: meta,
    child: Text(
      _formatWesternNumber(value),
      textDirection: textDirection,
      style: typography.tabular(typography.caption).copyWith(
            color: colors.textTertiary,
          ),
    ),
  );
}

List<FlSpot> _spotsForSeries(AppChartSeries series, int pointCount) {
  return List.generate(pointCount, (i) {
    final x = series.points.length > i
        ? (series.points[i].x ?? i.toDouble())
        : i.toDouble();
    return FlSpot(x, _pointY(series, i));
  });
}

double _pointY(AppChartSeries series, int index) {
  if (index >= series.points.length) return 0;
  return series.points[index].y;
}

int _maxPointCount(List<AppChartSeries> series) {
  if (series.isEmpty) return 0;
  return series
      .map((s) => s.points.length)
      .reduce((a, b) => a > b ? a : b);
}

List<String> _resolveXLabels(List<AppChartSeries> series, int pointCount) {
  if (series.isEmpty) return const [];
  final primary = series.first;
  return List.generate(pointCount, (i) {
    if (i < primary.points.length && primary.points[i].xLabel != null) {
      return primary.points[i].xLabel!;
    }
    return '${i + 1}';
  });
}

({double min, double max}) _computeYRange(
  List<AppChartSeries> series,
  double? yMin,
  double? yMax, {
  bool stacked = false,
}) {
  if (yMin != null && yMax != null) {
    return (min: yMin, max: yMax);
  }

  final pointCount = _maxPointCount(series);
  var maxValue = 1.0;
  var minValue = 0.0;

  if (stacked) {
    for (var i = 0; i < pointCount; i++) {
      var total = 0.0;
      for (final s in series) {
        total += _pointY(s, i);
      }
      maxValue = math.max(maxValue, total);
    }
  } else {
    for (final s in series) {
      for (final point in s.points) {
        maxValue = math.max(maxValue, point.y);
        minValue = math.min(minValue, point.y);
      }
    }
  }

  final resolvedMax = yMax ?? maxValue * 1.1;
  final resolvedMin = yMin ?? math.min(minValue, 0);
  if (resolvedMax <= resolvedMin) {
    return (min: resolvedMin, max: resolvedMin + 1);
  }
  return (min: resolvedMin, max: resolvedMax);
}

List<_DonutSlice> _donutSlices(List<AppChartSeries> series) {
  if (series.isEmpty) return const [];

  if (series.length == 1 && series.first.points.length > 1) {
    final s = series.first;
    return [
      for (var i = 0; i < s.points.length; i++)
        _DonutSlice(
          label: s.points[i].xLabel ?? '${s.name} ${i + 1}',
          value: s.points[i].y,
          color: s.color,
        ),
    ];
  }

  return [
    for (final s in series)
      _DonutSlice(
        label: s.name,
        value: s.points.isEmpty
            ? 0
            : s.points.map((p) => p.y).reduce((a, b) => a + b),
        color: s.color,
      ),
  ];
}

bool _hasChartData(List<AppChartSeries> series, AppChartType type) {
  if (series.isEmpty) return false;
  if (type == AppChartType.donut) {
    return _donutSlices(series).any((s) => s.value > 0);
  }
  return series.any((s) => s.points.isNotEmpty);
}

bool _supportsLegend(AppChartType type) {
  return type != AppChartType.donut && type != AppChartType.sparkline;
}

String _buildSemanticsLabel(List<AppChartSeries> series, AppChartType type) {
  final buffer = StringBuffer('Chart. ');
  if (type == AppChartType.donut) {
    final slices = _donutSlices(series);
    buffer.write(
      slices
          .map((s) => '${s.label} ${_formatWesternNumber(s.value)}')
          .join(', '),
    );
  } else {
    for (final s in series) {
      buffer.write('${s.name}: ');
      buffer.write(
        s.points
            .map((p) {
              final label = p.xLabel ?? p.x?.toString() ?? '';
              return label.isEmpty
                  ? _formatWesternNumber(p.y)
                  : '$label ${_formatWesternNumber(p.y)}';
            })
            .join(', '),
      );
      buffer.write('. ');
    }
  }
  return buffer.toString().trim();
}

String _sparklineSemanticsLabel(List<double> data) {
  if (data.isEmpty) return 'Sparkline, no data';
  final min = data.reduce(math.min);
  final max = data.reduce(math.max);
  return 'Sparkline trend from ${_formatWesternNumber(min)} '
      'to ${_formatWesternNumber(max)} across ${data.length} points';
}

String _formatWesternNumber(num value) {
  final text = value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return _toWesternDigits(text);
}

String _toWesternDigits(String value) {
  const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  var result = value;
  for (var i = 0; i < 10; i++) {
    result = result
        .replaceAll(eastern[i], '$i')
        .replaceAll(persian[i], '$i');
  }
  return result;
}
