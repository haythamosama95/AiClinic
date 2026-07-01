import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Minimum stepper shelf depth before layout measurement.
const double kEncounterHeaderStepperMinDepth = 58.0;

/// Default shoulder fillet radius for the encounter header stepper shelf.
const double kEncounterHeaderFilletRadius = 15.0;

/// Builds the joined encounter header outline: full-width top row with a
/// narrower, rounded stepper shelf attached below via smooth shoulders.
///
/// Shoulder fillets use a fixed fillet radius with fillet×fillet arc spans.
abstract final class EncounterJoinedHeaderPath {
  EncounterJoinedHeaderPath._();

  /// Stepper wall inset from each edge; always `2 ×` the resolved fillet radius.
  static double resolvedWallInset({
    required double stepperDepth,
    double stepperInset = 0,
    double filletRadius = kEncounterHeaderFilletRadius,
  }) {
    final fillet = filletRadius.clamp(0.0, stepperDepth / 2);
    return math.max(stepperInset, fillet * 2);
  }

  static Path build({
    required Size size,
    required double borderRadius,
    required double headerHeight,
    required double stepperDepth,
    double stepperInset = 0,
    double filletRadius = kEncounterHeaderFilletRadius,
    double shoulderShelfSpan = 0,
  }) {
    if (stepperDepth <= 0) {
      return _roundedRect(size: size, radius: borderRadius);
    }

    final width = size.width;
    final height = size.height;
    final radius = borderRadius.clamp(0.0, width / 2).clamp(0.0, height / 2).toDouble();
    final fillet = filletRadius.clamp(0.0, stepperDepth / 2).toDouble();
    final headerH = headerHeight.clamp(0.0, height).toDouble();
    final wallInset = resolvedWallInset(
      stepperDepth: stepperDepth,
      stepperInset: stepperInset,
      filletRadius: filletRadius,
    ).clamp(fillet * 2, (width - fillet * 2) / 2).toDouble();
    final stepperLeft = wallInset;
    final stepperRight = width - wallInset;
    final stepperWidth = stepperRight - stepperLeft;
    final stepperBottomRadius = radius.clamp(0.0, math.min(stepperWidth / 2, stepperDepth / 2)).toDouble();
    final shelfSpan = shoulderShelfSpan.clamp(0.0, double.infinity);

    final path = Path()
      ..moveTo(radius, 0)
      ..lineTo(width - radius, 0)
      ..arcToPoint(Offset(width, radius), radius: Radius.circular(radius));

    _appendRightShoulder(
      path,
      width: width,
      headerH: headerH,
      stepperRight: stepperRight,
      fillet: fillet,
      shelfSpan: shelfSpan,
    );

    path
      ..lineTo(stepperRight, height - stepperBottomRadius)
      ..arcToPoint(Offset(stepperRight - stepperBottomRadius, height), radius: Radius.circular(stepperBottomRadius))
      ..lineTo(stepperLeft + stepperBottomRadius, height)
      ..arcToPoint(Offset(stepperLeft, height - stepperBottomRadius), radius: Radius.circular(stepperBottomRadius));

    _appendLeftShoulder(path, stepperLeft: stepperLeft, headerH: headerH, fillet: fillet, shelfSpan: shelfSpan);

    path
      ..lineTo(0, radius)
      ..arcToPoint(Offset(radius, 0), radius: Radius.circular(radius))
      ..close();

    return path;
  }

  static void _appendRightShoulder(
    Path path, {
    required double width,
    required double headerH,
    required double stepperRight,
    required double fillet,
    double shelfSpan = 0,
  }) {
    path
      ..lineTo(width, headerH - fillet)
      ..arcToPoint(Offset(stepperRight + fillet, headerH), radius: Radius.circular(fillet), clockwise: true);

    if (shelfSpan > 0) {
      path.lineTo(stepperRight + fillet - shelfSpan, headerH);
    }

    path.arcTo(
      Rect.fromCircle(center: Offset(stepperRight + fillet, headerH + fillet), radius: fillet),
      -math.pi / 2,
      -math.pi / 2,
      false,
    );
  }

  static void _appendLeftShoulder(
    Path path, {
    required double stepperLeft,
    required double headerH,
    required double fillet,
    double shelfSpan = 0,
  }) {
    path
      ..lineTo(stepperLeft, headerH + fillet)
      ..arcTo(
        Rect.fromCircle(center: Offset(stepperLeft - fillet, headerH + fillet), radius: fillet),
        0,
        -math.pi / 2,
        false,
      );

    if (shelfSpan > 0) {
      path.lineTo(stepperLeft - fillet - shelfSpan, headerH);
    }

    path.arcToPoint(Offset(0, headerH - fillet), radius: Radius.circular(fillet), clockwise: true);
  }

  /// Horizontal shelf segment at [headerHeight] for painting overlays.
  ///
  /// When [spanToStepper] is true the line runs across the stepper inner width.
  /// Otherwise each shoulder extends inward by [shoulderShelfSpan] from its fillet.
  static ({Offset start, Offset end}) shoulderShelfLine({
    required Size size,
    required double headerHeight,
    required double stepperDepth,
    double stepperInset = 0,
    double filletRadius = kEncounterHeaderFilletRadius,
    double shoulderShelfSpan = 0,
    bool spanToStepper = false,
  }) {
    final fillet = filletRadius.clamp(0.0, stepperDepth / 2).toDouble();
    final wallInset = resolvedWallInset(
      stepperDepth: stepperDepth,
      stepperInset: stepperInset,
      filletRadius: filletRadius,
    );
    final stepperLeft = wallInset;
    final stepperRight = size.width - wallInset;
    final headerH = headerHeight;

    if (spanToStepper) {
      return (start: Offset(stepperLeft - fillet, headerH), end: Offset(stepperRight + fillet, headerH));
    }

    final span = shoulderShelfSpan.clamp(0.0, double.infinity);
    if (span <= 0) {
      return (start: Offset.zero, end: Offset.zero);
    }

    return (start: Offset(stepperLeft - fillet - span, headerH), end: Offset(stepperRight + fillet + span, headerH));
  }

  /// Content rectangle for the stepper shelf (inside shoulders).
  static Rect stepperShelfRect({
    required Size size,
    required double headerHeight,
    required double stepperDepth,
    double stepperInset = 0,
    double filletRadius = kEncounterHeaderFilletRadius,
  }) {
    final fillet = filletRadius.clamp(0.0, stepperDepth / 2).toDouble();
    final wallInset = resolvedWallInset(
      stepperDepth: stepperDepth,
      stepperInset: stepperInset,
      filletRadius: filletRadius,
    );
    final stepperLeft = wallInset;
    final stepperRight = size.width - wallInset;
    return Rect.fromLTRB(stepperLeft, headerHeight + fillet, stepperRight, size.height);
  }

  static Path _roundedRect({required Size size, required double radius}) {
    final r = radius.clamp(0.0, size.width / 2).clamp(0.0, size.height / 2);
    return Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), Radius.circular(r)));
  }
}

class EncounterJoinedHeaderClipper extends CustomClipper<Path> {
  const EncounterJoinedHeaderClipper({
    required this.borderRadius,
    required this.headerHeight,
    required this.stepperDepth,
    this.stepperInset = 0,
    this.filletRadius = kEncounterHeaderFilletRadius,
    this.shoulderShelfSpan = 0,
  });

  final double borderRadius;
  final double headerHeight;
  final double stepperDepth;
  final double stepperInset;
  final double filletRadius;
  final double shoulderShelfSpan;

  @override
  Path getClip(Size size) {
    final resolvedStepperDepth = math.max(0.0, size.height - headerHeight);
    return EncounterJoinedHeaderPath.build(
      size: size,
      borderRadius: borderRadius,
      headerHeight: headerHeight,
      stepperDepth: resolvedStepperDepth,
      stepperInset: stepperInset,
      filletRadius: filletRadius,
      shoulderShelfSpan: shoulderShelfSpan,
    );
  }

  @override
  bool shouldReclip(covariant EncounterJoinedHeaderClipper oldClipper) {
    return borderRadius != oldClipper.borderRadius ||
        headerHeight != oldClipper.headerHeight ||
        stepperDepth != oldClipper.stepperDepth ||
        stepperInset != oldClipper.stepperInset ||
        filletRadius != oldClipper.filletRadius ||
        shoulderShelfSpan != oldClipper.shoulderShelfSpan;
  }
}

class EncounterJoinedHeaderBorderPainter extends CustomPainter {
  const EncounterJoinedHeaderBorderPainter({
    required this.borderColor,
    required this.borderRadius,
    required this.headerHeight,
    required this.stepperDepth,
    this.stepperInset = 0,
    this.filletRadius = kEncounterHeaderFilletRadius,
    this.shoulderShelfSpan = 0,
    this.shoulderShelfSpanToStepper = false,
  });

  final Color borderColor;
  final double borderRadius;
  final double headerHeight;
  final double stepperDepth;
  final double stepperInset;
  final double filletRadius;
  final double shoulderShelfSpan;
  final bool shoulderShelfSpanToStepper;

  @override
  void paint(Canvas canvas, Size size) {
    final resolvedStepperDepth = math.max(0.0, size.height - headerHeight);
    final path = EncounterJoinedHeaderPath.build(
      size: size,
      borderRadius: borderRadius,
      headerHeight: headerHeight,
      stepperDepth: resolvedStepperDepth,
      stepperInset: stepperInset,
      filletRadius: filletRadius,
      shoulderShelfSpan: shoulderShelfSpan,
    );

    final paint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawPath(path, paint);

    if (shoulderShelfSpanToStepper || shoulderShelfSpan > 0) {
      final shelf = EncounterJoinedHeaderPath.shoulderShelfLine(
        size: size,
        headerHeight: headerHeight,
        stepperDepth: resolvedStepperDepth,
        stepperInset: stepperInset,
        filletRadius: filletRadius,
        shoulderShelfSpan: shoulderShelfSpan,
        spanToStepper: shoulderShelfSpanToStepper,
      );
      if (shelf.start != Offset.zero || shelf.end != Offset.zero) {
        canvas.drawLine(shelf.start, shelf.end, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant EncounterJoinedHeaderBorderPainter oldDelegate) {
    return borderColor != oldDelegate.borderColor ||
        borderRadius != oldDelegate.borderRadius ||
        headerHeight != oldDelegate.headerHeight ||
        stepperDepth != oldDelegate.stepperDepth ||
        stepperInset != oldDelegate.stepperInset ||
        filletRadius != oldDelegate.filletRadius ||
        shoulderShelfSpan != oldDelegate.shoulderShelfSpan ||
        shoulderShelfSpanToStepper != oldDelegate.shoulderShelfSpanToStepper;
  }
}
