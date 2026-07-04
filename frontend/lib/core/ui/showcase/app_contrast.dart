import 'package:flutter/material.dart';

/// WCAG 2.2 contrast ratio utilities — ported from web-reference contrast.ts.
abstract final class AppContrast {
  static double contrastRatio(Color foreground, Color background) {
    final l1 = _relativeLuminance(foreground);
    final l2 = _relativeLuminance(background);
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  static double contrastRatioHex(String foregroundHex, String backgroundHex) {
    return contrastRatio(hexToColor(foregroundHex), hexToColor(backgroundHex));
  }

  static String formatContrast(double ratio) => '${ratio.toStringAsFixed(2)}:1';

  static bool meetsAA(double ratio, {bool large = false}) {
    return large ? ratio >= 3 : ratio >= 4.5;
  }

  static double _relativeLuminance(Color color) {
    double channel(double s) {
      return s <= 0.03928
          ? s / 12.92
          : ((s + 0.055) / 1.055) * ((s + 0.055) / 1.055);
    }

    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  static Color hexToColor(String hex) {
    final normalized = hex.replaceAll('#', '');
    final value = normalized.length == 3
        ? normalized.split('').map((c) => c + c).join()
        : normalized;
    final num = int.parse(value, radix: 16);
    return Color(0xFF000000 | num);
  }
}
