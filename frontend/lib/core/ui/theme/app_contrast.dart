import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG contrast utilities aligned with `web-reference/src/lib/contrast.ts`.
abstract final class AppContrast {
  static double contrastRatio(Color foreground, Color background) {
    final l1 = _relativeLuminance(foreground);
    final l2 = _relativeLuminance(background);
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  static String formatContrast(double ratio) => '${ratio.toStringAsFixed(2)}:1';

  static bool meetsAA(double ratio, {bool large = false}) => large ? ratio >= 3 : ratio >= 4.5;

  static double _relativeLuminance(Color color) {
    double linearize(double value) {
      final s = value / 255;
      return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = linearize(color.r * 255);
    final g = linearize(color.g * 255);
    final b = linearize(color.b * 255);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }
}
