import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';

/// Receipt tear-line motif between services and totals on billing surfaces.
class InvoicePerforationDivider extends StatelessWidget {
  const InvoicePerforationDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space4),
      child: Row(
        children: [
          _Notch(colors: colors, mirrored: true),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const dotWidth = 6.0;
                const gap = 5.0;
                final count = (constraints.maxWidth / (dotWidth + gap)).floor().clamp(1, 120);

                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(count, (index) {
                    return Padding(
                      padding: EdgeInsets.only(right: index == count - 1 ? 0 : gap),
                      child: Container(
                        width: dotWidth,
                        height: 1.5,
                        decoration: BoxDecoration(
                          color: colors.borderDefault.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
          _Notch(colors: colors, mirrored: false),
        ],
      ),
    );
  }
}

class _Notch extends StatelessWidget {
  const _Notch({required this.colors, required this.mirrored});

  final AppSemanticColors colors;
  final bool mirrored;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(10, 18),
      painter: _NotchPainter(color: colors.borderSubtle, mirrored: mirrored),
    );
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
