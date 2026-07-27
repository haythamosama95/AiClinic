import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';

/// Which edge notches appear on when [showNotches] is true.
enum InvoicePerforationNotchEdge { top, bottom }

/// Receipt tear-line motif between services and totals on billing surfaces.
class InvoicePerforationDivider extends StatelessWidget {
  const InvoicePerforationDivider({
    super.key,
    this.dashWidth = 6,
    this.gap = 5,
    this.color,
    this.notchEdge = InvoicePerforationNotchEdge.top,
    this.showNotches = true,
    this.lineHeight = 1.5,
    this.verticalPadding = AppSpacing.space4,
    this.filled = false,
  });

  final double dashWidth;
  final double gap;
  final Color? color;
  final InvoicePerforationNotchEdge notchEdge;
  final bool showNotches;
  final double lineHeight;
  final double verticalPadding;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dashColor = color ?? colors.borderDefault.withValues(alpha: filled ? 0.4 : 0.55);

    final dashLine = LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / (dashWidth + gap)).floor().clamp(1, 120);

        if (filled) {
          return Row(
            children: List.generate(count, (index) {
              return Padding(
                padding: EdgeInsets.only(right: index == count - 1 ? 0 : gap),
                child: Container(
                  width: dashWidth,
                  height: lineHeight,
                  color: dashColor,
                ),
              );
            }),
          );
        }

        return CustomPaint(
          size: Size(constraints.maxWidth, lineHeight),
          painter: _DashedLinePainter(
            color: dashColor,
            dashWidth: dashWidth,
            gap: gap,
          ),
        );
      },
    );

    if (!showNotches) {
      if (verticalPadding == 0) {
        return dashLine;
      }
      return Padding(
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        child: dashLine,
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Row(
        children: [
          _Notch(colors: colors, mirrored: true, edge: notchEdge),
          Expanded(child: dashLine),
          _Notch(colors: colors, mirrored: false, edge: notchEdge),
        ],
      ),
    );
  }
}

class _Notch extends StatelessWidget {
  const _Notch({
    required this.colors,
    required this.mirrored,
    required this.edge,
  });

  final AppSemanticColors colors;
  final bool mirrored;
  final InvoicePerforationNotchEdge edge;

  @override
  Widget build(BuildContext context) {
    final child = CustomPaint(
      size: const Size(10, 18),
      painter: _NotchPainter(color: colors.borderSubtle, mirrored: mirrored),
    );

    return switch (edge) {
      InvoicePerforationNotchEdge.top => child,
      InvoicePerforationNotchEdge.bottom => Transform.flip(flipY: true, child: child),
    };
  }
}

class _NotchPainter extends CustomPainter {
  const _NotchPainter({required this.color, required this.mirrored});

  final Color color;
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final path = Path();
    if (mirrored) {
      path.moveTo(size.width, 0);
      path.quadraticBezierTo(0, size.height / 2, size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.quadraticBezierTo(size.width, size.height / 2, 0, size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _NotchPainter oldDelegate) => false;
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({
    required this.color,
    required this.dashWidth,
    required this.gap,
  });

  final Color color;
  final double dashWidth;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    var x = 0.0;
    while (x < size.width) {
      final end = (x + dashWidth).clamp(0.0, size.width).toDouble();
      canvas.drawLine(Offset(x, 0), Offset(end, 0), paint);
      x += dashWidth + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      color != oldDelegate.color ||
      dashWidth != oldDelegate.dashWidth ||
      gap != oldDelegate.gap;
}
