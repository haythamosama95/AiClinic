import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';

/// Card wrapper that renders a circulating border highlight behind [child].
///
/// The animated sweep travels around the perimeter while [active] is true.
/// Honors reduced-motion preferences with a static highlight border instead.
class AppAnimatedBorderCard extends StatefulWidget {
  const AppAnimatedBorderCard({
    required this.child,
    this.active = true,
    this.borderColor,
    this.highlightColor,
    this.borderRadius = AppRadius.lg,
    this.borderWidth = 2,
    this.duration = const Duration(milliseconds: 3200),
    super.key,
  });

  final Widget child;
  final bool active;
  final Color? borderColor;
  final Color? highlightColor;
  final double borderRadius;
  final double borderWidth;
  final Duration duration;

  @override
  State<AppAnimatedBorderCard> createState() => _AppAnimatedBorderCardState();
}

class _AppAnimatedBorderCardState extends State<AppAnimatedBorderCard> with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant AppAnimatedBorderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active || oldWidget.duration != widget.duration) {
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final shouldAnimate = widget.active && !AppMotion.prefersReducedMotion(context);
    if (shouldAnimate && _ticker == null) {
      _elapsed = Duration.zero;
      _ticker = createTicker((elapsed) {
        setState(() => _elapsed = elapsed);
      })..start();
    } else if (!shouldAnimate && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
      _elapsed = Duration.zero;
    }
  }

  double get _progress {
    if (widget.duration.inMicroseconds <= 0) {
      return 0;
    }
    return (_elapsed.inMicroseconds % widget.duration.inMicroseconds) / widget.duration.inMicroseconds;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return widget.child;
    }

    final colors = context.appColors;
    final baseBorder = widget.borderColor ?? colors.borderDefault;
    final highlight = widget.highlightColor ?? colors.actionPrimary;
    final reducedMotion = AppMotion.prefersReducedMotion(context);

    if (reducedMotion || _ticker == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(color: highlight.withValues(alpha: 0.75), width: widget.borderWidth),
        ),
        child: widget.child,
      );
    }

    final dim = baseBorder.withValues(alpha: 0.34);
    final peak = highlight;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: CustomPaint(
              painter: _CirculatingBorderPainter(
                progress: _progress,
                borderRadius: widget.borderRadius,
                borderWidth: widget.borderWidth,
                dimColor: dim,
                peakColor: peak,
              ),
            ),
          ),
        ),
        Padding(padding: EdgeInsets.all(widget.borderWidth), child: widget.child),
      ],
    );
  }
}

/// Paints a soft highlight that orbits the border with cosine falloff so the
/// loop has no visible seam when [progress] wraps from 1 back to 0.
class _CirculatingBorderPainter extends CustomPainter {
  const _CirculatingBorderPainter({
    required this.progress,
    required this.borderRadius,
    required this.borderWidth,
    required this.dimColor,
    required this.peakColor,
  });

  final double progress;
  final double borderRadius;
  final double borderWidth;
  final Color dimColor;
  final Color peakColor;

  static const _segmentCount = 96;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = borderWidth / 2;
    final innerRadius = math.max(0.0, borderRadius - inset);
    final rect = Rect.fromLTWH(inset, inset, size.width - borderWidth, size.height - borderWidth);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(innerRadius));
    final path = Path()..addRRect(rrect);
    final center = Offset(size.width / 2, size.height / 2);
    final highlightAngle = progress * 2 * math.pi;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (final metric in path.computeMetrics()) {
      final length = metric.length;
      final step = length / _segmentCount;

      for (var i = 0; i < _segmentCount; i++) {
        final start = i * step;
        final end = math.min(start + step + 0.5, length);
        final tangent = metric.getTangentForOffset(start + step / 2);
        if (tangent == null) {
          continue;
        }

        final delta = _angleDelta(
          math.atan2(tangent.position.dy - center.dy, tangent.position.dx - center.dx),
          highlightAngle,
        );
        final glow = math.pow(math.cos(delta * 1.35), 2).toDouble().clamp(0.0, 1.0);
        paint.color = Color.lerp(dimColor, peakColor, glow)!;

        canvas.drawPath(metric.extractPath(start, end), paint);
      }
    }
  }

  double _angleDelta(double a, double b) {
    var delta = a - b;
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta < -math.pi) {
      delta += 2 * math.pi;
    }
    return delta;
  }

  @override
  bool shouldRepaint(covariant _CirculatingBorderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.dimColor != dimColor ||
        oldDelegate.peakColor != peakColor;
  }
}
