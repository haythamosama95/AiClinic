import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';

/// Stack with a large tilted [icon] behind [child].
///
/// Used for queue cards and other dense rows where a muted watermark icon
/// reinforces the section meaning without competing with foreground content.
class TiltedBackgroundIconStack extends StatelessWidget {
  const TiltedBackgroundIconStack({
    required this.icon,
    required this.child,
    this.alignment = Alignment.centerLeft,
    this.iconRotation = defaultIconRotation,
    this.minIconSize = 76,
    this.iconColor,
    super.key,
  });

  final IconData icon;
  final Widget child;
  final Alignment alignment;
  final double iconRotation;
  final double minIconSize;
  final Color? iconColor;

  static const defaultIconRotation = math.pi / 6; // 30°
  static const defaultIconOpacity = 0.05;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final effectiveIconColor = iconColor ?? colors.mutedForeground.withValues(alpha: defaultIconOpacity);

    return LayoutBuilder(
      builder: (context, constraints) {
        final referenceHeight = constraints.hasBoundedHeight && constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : minIconSize / 1.4;
        final iconSize = math.max(minIconSize, referenceHeight * 1.4);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -iconSize * 0.12,
              top: 0,
              bottom: 0,
              child: Center(
                child: Transform.rotate(
                  angle: iconRotation,
                  child: Icon(icon, size: iconSize, color: effectiveIconColor),
                ),
              ),
            ),
            Align(alignment: alignment, child: child),
          ],
        );
      },
    );
  }
}
