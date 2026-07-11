import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

enum ProgressVariant { bar, circular, steps }

enum ProgressSize { sm, md }

/// Bar, circular, and step progress indicators (web `Progress`).
class AppProgress extends StatefulWidget {
  const AppProgress({
    this.variant = ProgressVariant.bar,
    this.value = 0,
    this.steps = 4,
    this.currentStep = 1,
    this.showLabel = false,
    this.indeterminate = false,
    this.size = ProgressSize.md,
    super.key,
  });

  final ProgressVariant variant;
  final double value;
  final int steps;
  final int currentStep;
  final bool showLabel;
  final bool indeterminate;
  final ProgressSize size;

  @override
  State<AppProgress> createState() => _AppProgressState();
}

class _AppProgressState extends State<AppProgress> with TickerProviderStateMixin {
  AnimationController? _barController;
  AnimationController? _spinController;

  double get _clampedValue => widget.value.clamp(0, 100);

  bool get _needsBarAnimation => widget.variant == ProgressVariant.bar && widget.indeterminate;

  bool get _needsSpinAnimation => widget.variant == ProgressVariant.circular && widget.indeterminate;

  @override
  void initState() {
    super.initState();
    _ensureControllers();
  }

  @override
  void didUpdateWidget(covariant AppProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureControllers();
    _syncAnimations();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimations();
  }

  void _ensureControllers() {
    if (_needsBarAnimation && _barController == null) {
      _barController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      );
    } else if (!_needsBarAnimation) {
      _barController?.dispose();
      _barController = null;
    }

    if (_needsSpinAnimation && _spinController == null) {
      _spinController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 1),
      );
    } else if (!_needsSpinAnimation) {
      _spinController?.dispose();
      _spinController = null;
    }
  }

  void _syncAnimations() {
    final reducedMotion = AppMotion.prefersReducedMotion(context);

    if (_barController != null) {
      if (reducedMotion) {
        _barController!.stop();
      } else if (!_barController!.isAnimating) {
        _barController!.repeat();
      }
    }

    if (_spinController != null) {
      if (reducedMotion) {
        _spinController!.stop();
      } else if (!_spinController!.isAnimating) {
        _spinController!.repeat();
      }
    }
  }

  @override
  void dispose() {
    _barController?.dispose();
    _spinController?.dispose();
    super.dispose();
  }

  double get _trackHeight => widget.size == ProgressSize.sm ? 4 : 6;

  @override
  Widget build(BuildContext context) {
    return switch (widget.variant) {
      ProgressVariant.circular => _buildCircular(context),
      ProgressVariant.steps => _buildSteps(context),
      ProgressVariant.bar => _buildBar(context),
    };
  }

  Widget _buildBar(BuildContext context) {
    final colors = context.appColors;
    final fraction = _clampedValue / 100;
    final label = widget.indeterminate ? 'Loading' : '${_clampedValue.round()}% complete';

    return Semantics(
      label: label,
      value: widget.indeterminate ? null : '${_clampedValue.round()}%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: SizedBox(
              height: _trackHeight,
              child: ColoredBox(
                color: colors.surfaceMuted,
                child: widget.indeterminate
                    ? _buildIndeterminateBar(colors)
                    : Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FractionallySizedBox(
                          widthFactor: fraction,
                          child: ColoredBox(color: colors.actionPrimary),
                        ),
                      ),
              ),
            ),
          ),
          if (widget.showLabel && !widget.indeterminate) ...[
            const SizedBox(height: AppSpacing.space1),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                '${_clampedValue.round()}%',
                style: AppTypography.caption(context).copyWith(
                  color: colors.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIndeterminateBar(AppSemanticColors colors) {
    final controller = _barController;
    if (controller == null || AppMotion.prefersReducedMotion(context)) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: 1 / 3,
          child: ColoredBox(color: colors.actionPrimary),
        ),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            final segmentWidth = trackWidth / 3;
            final offset = -segmentWidth + (segmentWidth * 4 * controller.value);

            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                PositionedDirectional(
                  start: offset,
                  top: 0,
                  width: segmentWidth,
                  height: _trackHeight,
                  child: ColoredBox(color: colors.actionPrimary),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCircular(BuildContext context) {
    final colors = context.appColors;
    final dimension = widget.size == ProgressSize.sm ? 20.0 : 28.0;
    final label = widget.indeterminate ? 'Loading' : '${_clampedValue.round()}% complete';

    Widget indicator = CustomPaint(
      size: Size.square(dimension),
      painter: _CircularProgressPainter(
        progress: _clampedValue / 100,
        trackColor: colors.surfaceMuted,
        progressColor: colors.actionPrimary,
        strokeWidth: 2,
        indeterminate: widget.indeterminate,
      ),
    );

    if (widget.indeterminate && _spinController != null && !AppMotion.prefersReducedMotion(context)) {
      indicator = RotationTransition(
        turns: _spinController!,
        child: indicator,
      );
    }

    return Semantics(
      label: label,
      value: widget.indeterminate ? null : '${_clampedValue.round()}%',
      child: indicator,
    );
  }

  Widget _buildSteps(BuildContext context) {
    final colors = context.appColors;
    final safeStep = widget.currentStep.clamp(1, widget.steps);

    return Semantics(
      label: 'Step $safeStep of ${widget.steps}',
      value: '$safeStep',
      child: Row(
        children: [
          for (var index = 0; index < widget.steps; index++) ...[
            if (index > 0) const SizedBox(width: AppSpacing.space1),
            Expanded(
              child: _StepSegment(
                stepNumber: index + 1,
                safeStep: safeStep,
                colors: colors,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepSegment extends StatelessWidget {
  const _StepSegment({
    required this.stepNumber,
    required this.safeStep,
    required this.colors,
  });

  final int stepNumber;
  final int safeStep;
  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    final isComplete = stepNumber < safeStep;
    final isCurrent = stepNumber == safeStep;
    final active = isComplete || isCurrent;

    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: AppMotion.instant,
        height: 4,
        decoration: BoxDecoration(
          color: active
              ? colors.actionPrimary.withValues(alpha: isCurrent ? 0.8 : 1)
              : colors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
      ),
    );
  }
}

class _CircularProgressPainter extends CustomPainter {
  const _CircularProgressPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
    required this.indeterminate,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;
  final bool indeterminate;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    if (indeterminate) {
      const visibleFraction = 0.25;
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * visibleFraction,
        false,
        progressPaint,
      );
    } else {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.indeterminate != indeterminate;
  }
}
