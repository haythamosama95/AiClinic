import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/providers/reduced_motion_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

enum AppProgressSize { sm, md }

enum AppProgressVariant { linear, circular }

/// Linear or circular progress indicator with reduced-motion support.
class AppProgress extends ConsumerStatefulWidget {
  const AppProgress({
    super.key,
    this.variant = AppProgressVariant.linear,
    this.value,
    this.indeterminate = false,
    this.size = AppProgressSize.md,
    this.showLabel = false,
  });

  final AppProgressVariant variant;
  final double? value;
  final bool indeterminate;
  final AppProgressSize size;
  final bool showLabel;

  @override
  ConsumerState<AppProgress> createState() => _AppProgressState();
}

class _AppProgressState extends ConsumerState<AppProgress>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  bool _reducedMotion(BuildContext context) {
    return ref.watch(reducedMotionProvider) ||
        AppMotion.isReducedMotion(context);
  }

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(AppProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.indeterminate != widget.indeterminate ||
        oldWidget.variant != widget.variant) {
      _syncController();
    }
  }

  void _syncController() {
    _controller?.dispose();
    _controller = null;

    if (!widget.indeterminate) return;

    final duration = widget.variant == AppProgressVariant.circular
        ? const Duration(seconds: 1)
        : const Duration(milliseconds: 1200);
    _controller = AnimationController(vsync: this, duration: duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  double get _clampedValue => (widget.value ?? 0).clamp(0, 100);

  double get _barHeight => widget.size == AppProgressSize.sm ? 4 : 6;

  double get _circularDimension => widget.size == AppProgressSize.sm ? 20 : 28;

  @override
  Widget build(BuildContext context) {
    final reduced = _reducedMotion(context);
    return widget.variant == AppProgressVariant.linear
        ? _buildLinear(context, reduced)
        : _buildCircular(context, reduced);
  }

  Widget _buildLinear(BuildContext context, bool reduced) {
    final colors = context.colors;
    final isIndeterminate = widget.indeterminate;
    final clamped = _clampedValue;

    Widget fill;
    if (isIndeterminate) {
      if (reduced || _controller == null) {
        fill = Align(
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: 0.33,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.actionPrimary,
                borderRadius: AppRadius.fullAll,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      } else {
        fill = AnimatedBuilder(
          animation: _controller!,
          builder: (context, child) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth = constraints.maxWidth;
                final barWidth = trackWidth / 3;
                final travel = trackWidth + barWidth;
                final offset = (_controller!.value * travel) - barWidth;
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    PositionedDirectional(
                      start: offset,
                      width: barWidth,
                      top: 0,
                      bottom: 0,
                      child: child!,
                    ),
                  ],
                );
              },
            );
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.actionPrimary,
              borderRadius: AppRadius.fullAll,
            ),
            child: const SizedBox.expand(),
          ),
        );
      }
    } else {
      fill = TweenAnimationBuilder<double>(
        tween: Tween(end: clamped / 100),
        duration: AppDurations.base,
        curve: AppCurves.linear,
        builder: (context, factor, child) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(widthFactor: factor, child: child),
          );
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.actionPrimary,
            borderRadius: AppRadius.fullAll,
          ),
          child: const SizedBox.expand(),
        ),
      );
    }

    return Semantics(
      label: isIndeterminate ? 'Loading' : '${clamped.round()}% complete',
      value: isIndeterminate ? null : '${clamped.round()}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: AppRadius.fullAll,
            child: ColoredBox(
              color: colors.surfaceMuted,
              child: SizedBox(height: _barHeight, child: fill),
            ),
          ),
          if (widget.showLabel && !isIndeterminate)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s1),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  '${clamped.round()}%',
                  style: context.typography.caption.copyWith(
                    color: colors.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCircular(BuildContext context, bool reduced) {
    final colors = context.colors;
    final dim = _circularDimension;
    const stroke = 2.0;
    final radius = (dim - stroke) / 2;
    final center = dim / 2;
    final isIndeterminate = widget.indeterminate;
    final clamped = _clampedValue;
    final sweep = isIndeterminate
        ? math.pi * 1.5
        : (clamped / 100) * 2 * math.pi;

    Widget indicator = CustomPaint(
      size: Size(dim, dim),
      painter: _CircularProgressPainter(
        trackColor: colors.surfaceMuted,
        progressColor: colors.actionPrimary,
        strokeWidth: stroke,
        radius: radius,
        center: center,
        sweepAngle: sweep,
      ),
    );

    if (isIndeterminate && !reduced && _controller != null) {
      indicator = RotationTransition(turns: _controller!, child: indicator);
    }

    return Semantics(
      label: isIndeterminate ? 'Loading' : '${clamped.round()}% complete',
      value: isIndeterminate ? null : '${clamped.round()}',
      child: SizedBox(width: dim, height: dim, child: indicator),
    );
  }
}

class _CircularProgressPainter extends CustomPainter {
  _CircularProgressPainter({
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
    required this.radius,
    required this.center,
    required this.sweepAngle,
  });

  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;
  final double radius;
  final double center;
  final double sweepAngle;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = Offset(center, center);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(offset, radius, trackPaint);
    canvas.drawArc(
      Rect.fromCircle(center: offset, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_CircularProgressPainter oldDelegate) {
    return oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.sweepAngle != sweepAngle;
  }
}
