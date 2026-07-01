import 'dart:math' as math;

import 'package:ai_clinic/features/visits/presentation/widgets/encounter_joined_header_path.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cardSize = Size(960, 140);
  const borderRadius = 12.0;
  const headerHeight = 72.0;
  const stepperDepth = 68.0;
  final fillet = kEncounterHeaderFilletRadius.clamp(0.0, stepperDepth / 2);
  final wallInset = EncounterJoinedHeaderPath.resolvedWallInset(stepperDepth: stepperDepth);

  group('EncounterJoinedHeaderPath.build', () {
    test('returns a closed path with stepper shelf', () {
      final path = EncounterJoinedHeaderPath.build(
        size: cardSize,
        borderRadius: borderRadius,
        headerHeight: headerHeight,
        stepperDepth: stepperDepth,
      );
      final metrics = path.computeMetrics().toList();

      expect(metrics, isNotEmpty);
      expect(metrics.last.isClosed, isTrue);
    });

    test('bounds match card size', () {
      final path = EncounterJoinedHeaderPath.build(
        size: cardSize,
        borderRadius: borderRadius,
        headerHeight: headerHeight,
        stepperDepth: stepperDepth,
      );
      final bounds = path.getBounds();

      expect(bounds.left, closeTo(0, 0.01));
      expect(bounds.top, closeTo(0, 0.01));
      expect(bounds.right, closeTo(cardSize.width, 0.01));
      expect(bounds.bottom, closeTo(cardSize.height, 0.01));
    });

    test('stepper shelf is narrower than the header body', () {
      final shelf = EncounterJoinedHeaderPath.stepperShelfRect(
        size: cardSize,
        headerHeight: headerHeight,
        stepperDepth: stepperDepth,
      );

      expect(shelf.width, lessThan(cardSize.width));
      expect(shelf.left, greaterThan(0));
      expect(shelf.right, lessThan(cardSize.width));
    });

    test('falls back to rounded rect when stepper depth is zero', () {
      final path = EncounterJoinedHeaderPath.build(
        size: cardSize,
        borderRadius: borderRadius,
        headerHeight: headerHeight,
        stepperDepth: 0,
      );

      expect(path.contains(const Offset(8, 8)), isTrue);
      expect(path.contains(Offset(cardSize.width / 2, cardSize.height / 2)), isTrue);
    });

    test('shoulder shelf span inserts horizontal segment between fillets', () {
      const span = 24.0;
      final path = EncounterJoinedHeaderPath.build(
        size: cardSize,
        borderRadius: borderRadius,
        headerHeight: headerHeight,
        stepperDepth: stepperDepth,
        shoulderShelfSpan: span,
      );
      final shelf = EncounterJoinedHeaderPath.shoulderShelfLine(
        size: cardSize,
        headerHeight: headerHeight,
        stepperDepth: stepperDepth,
        shoulderShelfSpan: span,
      );

      expect(path.computeMetrics().last.isClosed, isTrue);
      expect(shelf.start.dx, closeTo(wallInset - fillet - span, 0.01));
      expect(shelf.end.dx, closeTo(cardSize.width - wallInset + fillet + span, 0.01));
      expect(shelf.start.dy, closeTo(headerHeight, 0.01));
      expect(shelf.end.dy, closeTo(headerHeight, 0.01));
    });

    test('shoulder shelf span to stepper spans inner stepper width', () {
      final shelf = EncounterJoinedHeaderPath.shoulderShelfLine(
        size: cardSize,
        headerHeight: headerHeight,
        stepperDepth: stepperDepth,
        spanToStepper: true,
      );
      final stepperLeft = wallInset;
      final stepperRight = cardSize.width - wallInset;

      expect(shelf.start.dx, closeTo(stepperLeft - fillet, 0.01));
      expect(shelf.end.dx, closeTo(stepperRight + fillet, 0.01));
      expect(shelf.end.dx - shelf.start.dx, closeTo(stepperRight - stepperLeft + fillet * 2, 0.01));
    });

    test('right shoulder fillets mirror the left shoulder', () {
      final left = Path()
        ..moveTo(wallInset, headerHeight + fillet)
        ..arcTo(
          Rect.fromCircle(center: Offset(wallInset - fillet, headerHeight + fillet), radius: fillet),
          0,
          -math.pi / 2,
          false,
        )
        ..arcToPoint(Offset(0, headerHeight - fillet), radius: Radius.circular(fillet), clockwise: true);

      final right = Path()
        ..moveTo(cardSize.width, headerHeight - fillet)
        ..arcToPoint(
          Offset(cardSize.width - wallInset + fillet, headerHeight),
          radius: Radius.circular(fillet),
          clockwise: true,
        )
        ..arcTo(
          Rect.fromCircle(center: Offset(cardSize.width - wallInset + fillet, headerHeight + fillet), radius: fillet),
          -math.pi / 2,
          -math.pi / 2,
          false,
        );

      final leftMetric = left.computeMetrics().first;
      final rightMetric = right.computeMetrics().first;
      var maxAsymmetry = 0.0;

      for (var i = 0; i <= 200; i++) {
        final leftPoint = leftMetric.getTangentForOffset(leftMetric.length * i / 200)!.position;
        final mirrored = Offset(cardSize.width - leftPoint.dx, leftPoint.dy);
        final rightPoint = rightMetric.getTangentForOffset(rightMetric.length * (1 - i / 200))!.position;
        maxAsymmetry = math.max(maxAsymmetry, (rightPoint - mirrored).distance);
      }

      expect(maxAsymmetry, lessThan(0.01));
    });
  });
}
