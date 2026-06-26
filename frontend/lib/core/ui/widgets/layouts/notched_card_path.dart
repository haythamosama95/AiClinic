import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Default notch fillet radius tuned against the reference screenshot.
const double kNotchFilletRadius = 35.0;

/// Vertical drop from the main top edge to the notch shelf.
const double kNotchShelfDepth = 40.0;

/// Minimum horizontal shelf length when no actions are supplied.
const double kNotchMinWidth = 56.0;

/// Horizontal padding around the action row inside the notch shelf.
const double kNotchHorizontalPadding = SpacingTokens.sm;

/// Builds the closed outline path for the notched card shape.
///
/// [AppCard] parity targets (from `FCard` header/body): title and description use
/// forui card header insets; body uses standard card content padding — reserved
/// for `AppNotchedCard` in a later phase.
abstract final class NotchedCardPath {
  NotchedCardPath._();

  static Path build({
    required Size size,
    required double borderRadius,
    required double notchWidth,
    double shelfDepth = kNotchShelfDepth,
    double filletRadius = kNotchFilletRadius,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final width = size.width;
    final height = size.height;
    final radius = borderRadius.clamp(0.0, width / 2).clamp(0.0, height / 2);
    final fillet = filletRadius.clamp(0.0, shelfDepth / 2);
    final shelfWidth = notchWidth.clamp(0.0, width - radius - fillet * 2);

    final shelfEndX = width - fillet;
    final shelfLeftX = shelfEndX - shelfWidth;
    final mainTopEndX = shelfLeftX - fillet;

    final path = Path()
      ..moveTo(radius, 0)
      // Main top edge (leading → cut-out entry).
      ..lineTo(mainTopEndX, 0)
      // Entry upper fillet: main top curves downward.
      ..arcToPoint(Offset(shelfLeftX, fillet), radius: Radius.circular(fillet), clockwise: true)
      ..lineTo(shelfLeftX, shelfDepth - fillet)
      // Entry lower fillet: bottom-left quarter-arc (π → π/2, counter-clockwise).
      ..arcTo(
        Rect.fromCircle(center: Offset(shelfLeftX + fillet, shelfDepth - fillet), radius: fillet),
        math.pi,
        -math.pi / 2,
        false,
      )
      // Notch shelf (actions float here).
      ..lineTo(shelfEndX, shelfDepth)
      // Exit fillet: quarter-arc down onto trailing edge; top-trailing corner stays open.
      ..arcToPoint(Offset(width, shelfDepth + fillet), radius: Radius.circular(fillet), clockwise: true)
      ..lineTo(width, height - radius)
      ..arcToPoint(Offset(width - radius, height), radius: Radius.circular(radius))
      ..lineTo(radius, height)
      ..arcToPoint(Offset(0, height - radius), radius: Radius.circular(radius))
      ..lineTo(0, radius)
      ..arcToPoint(Offset(radius, 0), radius: Radius.circular(radius))
      ..close();

    if (textDirection == TextDirection.rtl) {
      final mirror = Matrix4.identity()
        ..setEntry(0, 0, -1)
        ..setEntry(0, 3, width);
      return path.transform(mirror.storage);
    }

    return path;
  }

  /// Shelf rectangle for positioning floating actions (LTR coordinates).
  static Rect shelfRect({
    required Size size,
    required double borderRadius,
    required double notchWidth,
    double shelfDepth = kNotchShelfDepth,
    double filletRadius = kNotchFilletRadius,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final width = size.width;
    final radius = borderRadius.clamp(0.0, width / 2);
    final fillet = filletRadius.clamp(0.0, shelfDepth / 2);
    final shelfWidth = notchWidth.clamp(0.0, width - radius - fillet * 2);
    final shelfEndX = width - fillet;
    final shelfLeftX = shelfEndX - shelfWidth;

    final rect = Rect.fromLTRB(shelfLeftX, 0, shelfEndX, shelfDepth);

    if (textDirection == TextDirection.rtl) {
      return Rect.fromLTRB(width - rect.right, rect.top, width - rect.left, rect.bottom);
    }

    return rect;
  }
}

/// Clips child content to the notched card outline.
class NotchedCardClipper extends CustomClipper<Path> {
  const NotchedCardClipper({
    required this.borderRadius,
    required this.notchWidth,
    this.shelfDepth = kNotchShelfDepth,
    this.filletRadius = kNotchFilletRadius,
    this.textDirection = TextDirection.ltr,
  });

  final double borderRadius;
  final double notchWidth;
  final double shelfDepth;
  final double filletRadius;
  final TextDirection textDirection;

  @override
  Path getClip(Size size) {
    return NotchedCardPath.build(
      size: size,
      borderRadius: borderRadius,
      notchWidth: notchWidth,
      shelfDepth: shelfDepth,
      filletRadius: filletRadius,
      textDirection: textDirection,
    );
  }

  @override
  bool shouldReclip(covariant NotchedCardClipper oldClipper) {
    return borderRadius != oldClipper.borderRadius ||
        notchWidth != oldClipper.notchWidth ||
        shelfDepth != oldClipper.shelfDepth ||
        filletRadius != oldClipper.filletRadius ||
        textDirection != oldClipper.textDirection;
  }
}

/// Strokes the notched card outline using the same path as [NotchedCardClipper].
class NotchedCardBorderPainter extends CustomPainter {
  const NotchedCardBorderPainter({
    required this.borderColor,
    required this.borderRadius,
    required this.notchWidth,
    this.shelfDepth = kNotchShelfDepth,
    this.filletRadius = kNotchFilletRadius,
    this.textDirection = TextDirection.ltr,
  });

  final Color borderColor;
  final double borderRadius;
  final double notchWidth;
  final double shelfDepth;
  final double filletRadius;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final path = NotchedCardPath.build(
      size: size,
      borderRadius: borderRadius,
      notchWidth: notchWidth,
      shelfDepth: shelfDepth,
      filletRadius: filletRadius,
      textDirection: textDirection,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant NotchedCardBorderPainter oldDelegate) {
    return borderColor != oldDelegate.borderColor ||
        borderRadius != oldDelegate.borderRadius ||
        notchWidth != oldDelegate.notchWidth ||
        shelfDepth != oldDelegate.shelfDepth ||
        filletRadius != oldDelegate.filletRadius ||
        textDirection != oldDelegate.textDirection;
  }
}
