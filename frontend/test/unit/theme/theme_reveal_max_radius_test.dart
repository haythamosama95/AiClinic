import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/theme_transition_controller.dart';

void main() {
  group('themeRevealMaxRadius', () {
    test('covers viewport corners from center', () {
      const viewport = Size(800, 600);
      const center = Offset(400, 300);

      final radius = themeRevealMaxRadius(center, viewport);

      expect(radius, closeTo(500, 0.001));
    });

    test('uses farthest corner from off-center origin', () {
      const viewport = Size(800, 600);
      const origin = Offset(100, 50);

      final radius = themeRevealMaxRadius(origin, viewport);

      expect(radius, closeTo(890.2246907382428, 0.001));
    });
  });
}
