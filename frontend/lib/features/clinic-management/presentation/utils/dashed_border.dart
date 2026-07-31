import 'package:flutter/material.dart';

/// Rounded dashed border (web `border-dashed`); Flutter has no built-in dashed [Border].
class DashedBorder extends StatelessWidget {
  const DashedBorder({
    required this.child,
    required this.color,
    this.borderRadius = BorderRadius.zero,
    this.dashWidth = 5,
    this.dashSpace = 4,
    super.key,
  });

  final Widget child;
  final Color color;
  final BorderRadius borderRadius;
  final double dashWidth;
  final double dashSpace;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: color,
        borderRadius: borderRadius,
        dashWidth: dashWidth,
        dashSpace: dashSpace,
      ),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.color,
    required this.borderRadius,
    required this.dashWidth,
    required this.dashSpace,
  });

  final Color color;
  final BorderRadius borderRadius;
  final double dashWidth;
  final double dashSpace;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, end.clamp(0, metric.length)), paint);
        distance = end + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return color != oldDelegate.color ||
        borderRadius != oldDelegate.borderRadius ||
        dashWidth != oldDelegate.dashWidth ||
        dashSpace != oldDelegate.dashSpace;
  }
}
