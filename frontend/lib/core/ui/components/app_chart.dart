import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Chart type enumeration matching web `AppChartProps.type`.
/// `area` is accepted but renders identically to `line` (matches web).
enum AppChartType { line, area, bar, stackedBar, donut }

/// A single data series for [AppChart].
class ChartSeries {
  const ChartSeries({required this.label, required this.data, this.color});

  final String label;
  final List<num> data;
  final Color? color;
}

/// Categorical chart palette from design-system primitives.
/// Matches web `chartPalette`: action-primary, status-info, success, warning, text-tertiary, action-ai.
const chartPalette = <Color>[
  AppColorPrimitives.teal600,
  AppColorPrimitives.blue500,
  AppColorPrimitives.green500,
  AppColorPrimitives.amber500,
  AppColorPrimitives.neutral500,
  AppColorPrimitives.violet600,
];

/// Resolves chart palette colors from the current theme for proper dark-mode support.
List<Color> chartPaletteOf(BuildContext context) {
  final c = context.appColors;
  return [
    c.actionPrimary,
    AppColorPrimitives.blue500,
    c.statusSuccessFg,
    AppColorPrimitives.amber500,
    c.textTertiary,
    c.actionAi,
  ];
}

/// Hand-rolled chart widget using [CustomPaint] — no chart library dependency.
///
/// Supports line, bar, stacked-bar, and donut chart types.
/// `area` is accepted but renders as a line chart (matches web).
class AppChart extends StatelessWidget {
  const AppChart({
    super.key,
    required this.type,
    required this.series,
    this.labels,
    this.height = 200,
    this.ariaLabel = 'Chart',
  });

  final AppChartType type;
  final List<ChartSeries> series;
  final List<String>? labels;
  final double height;
  final String ariaLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final palette = chartPaletteOf(context);

    return Semantics(
      label: ariaLabel,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          border: Border.all(color: colors.borderDefault),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: _buildChart(context, palette),
      ),
    );
  }

  Widget _buildChart(BuildContext context, List<Color> palette) {
    switch (type) {
      case AppChartType.line:
      case AppChartType.area:
        return _LineChartWidget(series: series, labels: labels, height: height, palette: palette);
      case AppChartType.bar:
        return _BarChartWidget(series: series, height: height, palette: palette, stacked: false);
      case AppChartType.stackedBar:
        return _BarChartWidget(series: series, height: height, palette: palette, stacked: true);
      case AppChartType.donut:
        return _DonutChartWidget(series: series, height: height, palette: palette);
    }
  }
}

/// Minimal sparkline chart for use in [AppMetricCard] and similar contexts.
class AppChartSparkline extends StatelessWidget {
  const AppChartSparkline({super.key, required this.data, required this.color, this.width = 80, this.height = 24});

  final List<num> data;
  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _SparklinePainter(data: data, color: color),
    );
  }
}

// ---------------------------------------------------------------------------
// Line chart
// ---------------------------------------------------------------------------

class _LineChartWidget extends StatelessWidget {
  const _LineChartWidget({required this.series, required this.height, required this.palette, this.labels});

  final List<ChartSeries> series;
  final double height;
  final List<Color> palette;
  final List<String>? labels;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return CustomPaint(
                size: Size(constraints.maxWidth, height),
                painter: _LineChartPainter(series: series, palette: palette, gridColor: colors.borderSubtle),
              );
            },
          ),
        ),
        if (series.length > 1 || series.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.space2),
            child: Wrap(
              spacing: AppSpacing.space4,
              runSpacing: AppSpacing.space1,
              children: [
                for (var i = 0; i < series.length; i++)
                  _LegendItem(color: series[i].color ?? palette[i % palette.length], label: series[i].label),
              ],
            ),
          ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({required this.series, required this.palette, required this.gridColor});

  final List<ChartSeries> series;
  final List<Color> palette;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 24.0;
    final innerH = size.height - padding * 2;

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;

    for (final pct in [0.25, 0.5, 0.75]) {
      final y = padding + innerH * pct;
      canvas.drawLine(Offset(padding, y), Offset(size.width - padding, y), gridPaint);
    }

    for (var si = 0; si < series.length; si++) {
      final s = series[si];
      final color = s.color ?? palette[si % palette.length];
      final points = _normalizeData(s.data, size.width, size.height, padding);

      final linePaint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      if (points.isNotEmpty) {
        final path = Path()..moveTo(points[0].dx, points[0].dy);
        for (var i = 1; i < points.length; i++) {
          path.lineTo(points[i].dx, points[i].dy);
        }
        canvas.drawPath(path, linePaint);

        for (final p in points) {
          canvas.drawCircle(p, 3, dotPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      series != oldDelegate.series || palette != oldDelegate.palette;
}

// ---------------------------------------------------------------------------
// Bar chart (regular + stacked)
// ---------------------------------------------------------------------------

class _BarChartWidget extends StatelessWidget {
  const _BarChartWidget({required this.series, required this.height, required this.palette, required this.stacked});

  final List<ChartSeries> series;
  final double height;
  final List<Color> palette;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return CustomPaint(
                size: Size(constraints.maxWidth, height),
                painter: _BarChartPainter(series: series, palette: palette, stacked: stacked),
              );
            },
          ),
        ),
        if (series.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.space2),
            child: Wrap(
              spacing: AppSpacing.space4,
              runSpacing: AppSpacing.space1,
              children: [
                for (var i = 0; i < series.length; i++)
                  _LegendItem(color: series[i].color ?? palette[i % palette.length], label: series[i].label),
              ],
            ),
          ),
      ],
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({required this.series, required this.palette, required this.stacked});

  final List<ChartSeries> series;
  final List<Color> palette;
  final bool stacked;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    const padding = 24.0;
    final count = series[0].data.length;
    if (count == 0) return;

    final barGroupWidth = (size.width - padding * 2) / count;

    final double maxVal;
    if (stacked) {
      var m = 1.0;
      for (var i = 0; i < count; i++) {
        var sum = 0.0;
        for (final s in series) {
          sum += (i < s.data.length ? s.data[i].toDouble() : 0);
        }
        if (sum > m) m = sum;
      }
      maxVal = m;
    } else {
      var m = 1.0;
      for (final s in series) {
        for (final v in s.data) {
          if (v.toDouble() > m) m = v.toDouble();
        }
      }
      maxVal = m;
    }

    final barRadius = Radius.circular(2);

    for (var i = 0; i < count; i++) {
      final x = padding + i * barGroupWidth + barGroupWidth * 0.15;
      final w = barGroupWidth * 0.7 / (stacked ? 1 : series.length);
      var yOffset = size.height - padding;

      for (var si = 0; si < series.length; si++) {
        final value = si < series.length && i < series[si].data.length ? series[si].data[i].toDouble() : 0.0;
        final barH = (value / maxVal) * (size.height - padding * 2);
        final color = series[si].color ?? palette[si % palette.length];
        final paint = Paint()..color = color;

        final double bx;
        final double by;
        if (stacked) {
          yOffset -= barH;
          bx = x;
          by = yOffset;
        } else {
          bx = x + si * w;
          by = size.height - padding - barH;
        }

        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, w, barH), barRadius), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      series != oldDelegate.series || stacked != oldDelegate.stacked;
}

// ---------------------------------------------------------------------------
// Donut chart
// ---------------------------------------------------------------------------

class _DonutChartWidget extends StatelessWidget {
  const _DonutChartWidget({required this.series, required this.height, required this.palette});

  final List<ChartSeries> series;
  final double height;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    final data = series.isNotEmpty ? series[0].data : <num>[];
    final labels = series.map((s) => s.label).toList();
    final total = data.fold<double>(0, (a, b) => a + b.toDouble());
    final effectiveTotal = total == 0 ? 1.0 : total;

    final slices = <_DonutSlice>[];
    for (var i = 0; i < data.length; i++) {
      slices.add(
        _DonutSlice(
          label: i < labels.length ? labels[i] : 'Series $i',
          value: data[i].toDouble(),
          color: palette[i % palette.length],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: height,
          height: height,
          child: CustomPaint(
            size: Size(height, height),
            painter: _DonutChartPainter(
              slices: slices,
              total: effectiveTotal,
              centerColor: context.appColors.surfaceDefault,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.space6),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final slice in slices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: slice.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: AppSpacing.space2),
                    Text(
                      '${slice.label}: ',
                      style: AppTypography.caption(context).copyWith(color: context.appColors.textSecondary),
                    ),
                    Text(
                      slice.value.toInt().toString(),
                      style: AppTypography.caption(context).copyWith(
                        color: context.appColors.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DonutSlice {
  const _DonutSlice({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;
}

class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter({required this.slices, required this.total, required this.centerColor});

  final List<_DonutSlice> slices;
  final double total;
  final Color centerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(cx, cy) - 16;
    final innerR = r * 0.55;
    final center = Offset(cx, cy);

    var startAngle = -math.pi / 2;

    for (final slice in slices) {
      final sweepAngle = (slice.value / total) * 2 * math.pi;
      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.fill;

      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + r * math.cos(startAngle), center.dy + r * math.sin(startAngle))
        ..arcTo(Rect.fromCircle(center: center, radius: r), startAngle, sweepAngle, false)
        ..close();

      canvas.drawPath(path, paint);
      startAngle += sweepAngle;
    }

    canvas.drawCircle(center, innerR, Paint()..color = centerColor);
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      slices != oldDelegate.slices || total != oldDelegate.total;
}

// ---------------------------------------------------------------------------
// Sparkline
// ---------------------------------------------------------------------------

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.data, required this.color});

  final List<num> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final points = _normalizeData(data, size.width, size.height, 2);
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => data != oldDelegate.data || color != oldDelegate.color;
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

List<Offset> _normalizeData(List<num> data, double width, double height, double padding) {
  if (data.isEmpty) return [];
  var max = data.first.toDouble();
  var min = data.first.toDouble();
  for (var i = 1; i < data.length; i++) {
    final v = data[i].toDouble();
    if (v > max) max = v;
    if (v < min) min = v;
  }
  min = min.clamp(double.negativeInfinity, 0.0);
  final range = (max - min) == 0 ? 1.0 : (max - min);
  final innerW = width - padding * 2;
  final innerH = height - padding * 2;
  final divisor = math.max(data.length - 1, 1);

  return List.generate(data.length, (i) {
    final x = padding + (i / divisor) * innerW;
    final y = padding + innerH - ((data[i].toDouble() - min) / range) * innerH;
    return Offset(x, y);
  });
}

/// Legend dot + label used below line and bar charts.
class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppTypography.caption(context).copyWith(color: context.appColors.textSecondary)),
      ],
    );
  }
}
