import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';

/// Tree lines connecting a group header to its child nav items.
class ShellNavTreeConnector extends StatelessWidget {
  const ShellNavTreeConnector({required this.childCount, super.key});

  final int childCount;

  @override
  Widget build(BuildContext context) {
    if (childCount == 0) return const SizedBox.shrink();

    final lineColor = context.semanticColors.border.withValues(alpha: 0.4);
    final height = childCount * ShellTokens.itemHeight;

    return SizedBox(
      width: 28,
      height: height,
      child: CustomPaint(
        painter: _ShellNavTreeConnectorPainter(
          childCount: childCount,
          lineColor: lineColor,
          rowHeight: ShellTokens.itemHeight,
        ),
      ),
    );
  }
}

class _ShellNavTreeConnectorPainter extends CustomPainter {
  _ShellNavTreeConnectorPainter({required this.childCount, required this.lineColor, required this.rowHeight});

  final int childCount;
  final Color lineColor;
  final double rowHeight;

  static const double _verticalX = 18;
  static const double _branchEndX = 26;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final verticalBottom = childCount * rowHeight - rowHeight / 2;
    canvas.drawLine(const Offset(_verticalX, 0), Offset(_verticalX, verticalBottom), paint);

    for (var i = 0; i < childCount; i++) {
      final y = i * rowHeight + rowHeight / 2;
      final path = Path()
        ..moveTo(_verticalX, y)
        ..quadraticBezierTo(_verticalX + 4, y, _branchEndX, y);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ShellNavTreeConnectorPainter oldDelegate) {
    return oldDelegate.childCount != childCount || oldDelegate.lineColor != lineColor;
  }
}
