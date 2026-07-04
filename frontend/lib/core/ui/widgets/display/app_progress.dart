import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Visual variant for [AppProgress].
enum AppProgressVariant { bar, circular, steps }

/// Size scale for bar and circular [AppProgress].
enum AppProgressSize { sm, md }

/// Bar, circular, and segmented step progress indicators.
class AppProgress extends StatefulWidget {
  const AppProgress({
    this.variant = AppProgressVariant.bar,
    this.value = 0,
    this.steps = 4,
    this.currentStep = 1,
    this.showLabel = false,
    this.indeterminate = false,
    this.size = AppProgressSize.md,
    super.key,
  });

  final AppProgressVariant variant;
  final double value;
  final int steps;
  final int currentStep;
  final bool showLabel;
  final bool indeterminate;
  final AppProgressSize size;

  @override
  State<AppProgress> createState() => _AppProgressState();
}

class _AppProgressState extends State<AppProgress> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  double get _clampedValue => widget.value.clamp(0, 100);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant AppProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.indeterminate != oldWidget.indeterminate || widget.variant != oldWidget.variant) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    final reduced = AppMotion.reduced(context);
    final needsAnimation = widget.indeterminate && !reduced;

    if (needsAnimation) {
      final duration = widget.variant == AppProgressVariant.circular
          ? const Duration(milliseconds: 1000)
          : const Duration(milliseconds: 1200);
      _controller ??= AnimationController(vsync: this, duration: duration)..repeat();
    } else {
      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.variant) {
      AppProgressVariant.circular => _buildCircular(context),
      AppProgressVariant.steps => _buildSteps(context),
      AppProgressVariant.bar => _buildBar(context),
    };
  }

  Widget _buildCircular(BuildContext context) {
    final colors = context.colors;
    final reduced = AppMotion.reduced(context);
    final dim = switch (widget.size) {
      AppProgressSize.sm => AppSpacing.s5,
      AppProgressSize.md => AppSpacing.s6 + AppSpacing.s2,
    };
    const stroke = AppSpacing.sPx + AppSpacing.sPx;
    final radius = (dim - stroke) / 2;
    final circumference = 2 * math.pi * radius;
    final offset = widget.indeterminate && !reduced
        ? circumference * 0.75
        : circumference - (_clampedValue / 100) * circumference;

    Widget indicator = SizedBox(
      width: dim,
      height: dim,
      child: CustomPaint(
        painter: _CircularProgressPainter(
          trackColor: colors.surfaceMuted,
          fillColor: colors.actionPrimary,
          strokeWidth: stroke,
          radius: radius,
          center: dim / 2,
          dashOffset: offset,
          circumference: circumference,
        ),
      ),
    );

    if (_controller != null) {
      indicator = RotationTransition(turns: _controller!, child: indicator);
    }

    return Semantics(
      label: widget.indeterminate ? 'Loading' : '${_clampedValue.round()}% complete',
      value: widget.indeterminate ? null : '${_clampedValue.round()}',
      child: indicator,
    );
  }

  Widget _buildSteps(BuildContext context) {
    final colors = context.colors;
    final reduced = AppMotion.reduced(context);
    final safeStep = widget.currentStep.clamp(1, widget.steps);

    return Semantics(
      label: 'Step $safeStep of ${widget.steps}',
      value: '$safeStep',
      child: Row(
        children: [
          for (var i = 1; i <= widget.steps; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(end: i < widget.steps ? AppSpacing.s1 : 0),
                child: AnimatedContainer(
                  duration: reduced ? AppDurations.instant : AppDurations.instant,
                  curve: AppEasings.standard,
                  height: AppSpacing.s1,
                  decoration: BoxDecoration(
                    color: i <= safeStep
                        ? colors.actionPrimary.withValues(alpha: i == safeStep ? 0.8 : 1)
                        : colors.surfaceMuted,
                    borderRadius: AppRadii.fullAll,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBar(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final reduced = AppMotion.reduced(context);
    final trackHeight = switch (widget.size) {
      AppProgressSize.sm => AppSpacing.s1,
      AppProgressSize.md => AppSpacing.s1 + AppSpacing.s0_5,
    };

    Widget fill;
    if (widget.indeterminate && !reduced && _controller != null) {
      fill = LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = constraints.maxWidth;
          final fillWidth = trackWidth / 3;
          final travel = trackWidth + fillWidth;
          return AnimatedBuilder(
            animation: _controller!,
            builder: (context, _) {
              final dx = -fillWidth + travel * _controller!.value;
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  PositionedDirectional(
                    start: dx,
                    width: fillWidth,
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: colors.actionPrimary, borderRadius: AppRadii.fullAll),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } else if (widget.indeterminate) {
      fill = FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: 1 / 3,
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.actionPrimary, borderRadius: AppRadii.fullAll),
        ),
      );
    } else {
      fill = AnimatedFractionallySizedBox(
        duration: reduced ? AppDurations.instant : AppDurations.base,
        curve: AppEasings.linear,
        alignment: AlignmentDirectional.centerStart,
        widthFactor: _clampedValue / 100,
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.actionPrimary, borderRadius: AppRadii.fullAll),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: widget.indeterminate ? 'Loading' : '${_clampedValue.round()}% complete',
          value: widget.indeterminate ? null : '${_clampedValue.round()}',
          child: ClipRRect(
            borderRadius: AppRadii.fullAll,
            child: SizedBox(
              height: trackHeight,
              width: double.infinity,
              child: ColoredBox(color: colors.surfaceMuted, child: fill),
            ),
          ),
        ),
        if (widget.showLabel)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: AppSpacing.s1),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                '${_clampedValue.round()}%',
                style: typography.tabular(typography.caption).copyWith(color: colors.textTertiary),
              ),
            ),
          ),
      ],
    );
  }
}

class _CircularProgressPainter extends CustomPainter {
  _CircularProgressPainter({
    required this.trackColor,
    required this.fillColor,
    required this.strokeWidth,
    required this.radius,
    required this.center,
    required this.dashOffset,
    required this.circumference,
  });

  final Color trackColor;
  final Color fillColor;
  final double strokeWidth;
  final double radius;
  final double center;
  final double dashOffset;
  final double circumference;

  @override
  void paint(Canvas canvas, Size size) {
    final centerOffset = Offset(center, center);
    final rect = Rect.fromCircle(center: centerOffset, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(centerOffset, radius, trackPaint);

    final progressLength = circumference - dashOffset;
    if (progressLength <= 0) return;

    final progressPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, progressLength / radius, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.dashOffset != dashOffset ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.fillColor != fillColor;
  }
}
