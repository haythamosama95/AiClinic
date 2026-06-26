import 'package:ai_clinic/core/ui/widgets/layouts/notched_card_path.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cardSize = Size(320, 200);
  const borderRadius = 8.0;
  const notchWidth = kNotchMinWidth;

  Path buildPath({TextDirection textDirection = TextDirection.ltr}) {
    return NotchedCardPath.build(
      size: cardSize,
      borderRadius: borderRadius,
      notchWidth: notchWidth,
      textDirection: textDirection,
    );
  }

  group('NotchedCardPath.build', () {
    test('returns a closed path', () {
      final path = buildPath();
      final metrics = path.computeMetrics().toList();

      expect(metrics, isNotEmpty);
      expect(metrics.last.isClosed, isTrue);
    });

    test('bounds match card size', () {
      final path = buildPath();
      final bounds = path.getBounds();

      expect(bounds.left, closeTo(0, 0.01));
      expect(bounds.top, closeTo(0, 0.01));
      expect(bounds.right, closeTo(cardSize.width, 0.01));
      expect(bounds.bottom, closeTo(cardSize.height, 0.01));
    });

    test('LTR notch recess is on the trailing side', () {
      final path = buildPath();
      final shelf = NotchedCardPath.shelfRect(size: cardSize, borderRadius: borderRadius, notchWidth: notchWidth);

      expect(shelf.center.dx, greaterThan(cardSize.width / 2));

      final recessPoint = Offset(shelf.center.dx, kNotchShelfDepth / 2);
      expect(path.contains(recessPoint), isFalse);

      final bodyPoint = Offset(borderRadius + 20, cardSize.height / 2);
      expect(path.contains(bodyPoint), isTrue);
    });

    test('RTL mirrors notch to the leading side', () {
      final rtlShelf = NotchedCardPath.shelfRect(
        size: cardSize,
        borderRadius: borderRadius,
        notchWidth: notchWidth,
        textDirection: TextDirection.rtl,
      );

      expect(rtlShelf.center.dx, lessThan(cardSize.width / 2));
    });
  });

  group('NotchedCardClipper', () {
    test('getClip reuses path builder', () {
      const clipper = NotchedCardClipper(borderRadius: borderRadius, notchWidth: notchWidth);
      final clipPath = clipper.getClip(cardSize);
      final builtPath = buildPath();

      expect(clipPath.getBounds(), builtPath.getBounds());
    });
  });
}
