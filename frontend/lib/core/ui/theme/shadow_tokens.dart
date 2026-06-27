import 'package:flutter/material.dart';

/// Elevation shadows derived from the Tailwind `--shadow-*` custom properties.
///
/// Shadow color is `hsl(0 0% 10.1961%)` ≈ `#1a1a1a`.
abstract final class ShadowTokens {
  static const Color _shadowColor = Color(0xFF1A1A1A);

  static const List<BoxShadow> shadow2xs = [
    BoxShadow(color: Color(0x0D1A1A1A), offset: Offset(0, 1), blurRadius: 3, spreadRadius: 0),
  ];

  static const List<BoxShadow> shadowXs = shadow2xs;

  static const List<BoxShadow> shadowSm = [
    BoxShadow(color: Color(0x1A1A1A1A), offset: Offset(0, 1), blurRadius: 3, spreadRadius: 0),
    BoxShadow(color: Color(0x1A1A1A1A), offset: Offset(0, 1), blurRadius: 2, spreadRadius: -1),
  ];

  static const List<BoxShadow> shadow = shadowSm;

  static const List<BoxShadow> shadowMd = [
    BoxShadow(color: Color(0x1A1A1A1A), offset: Offset(0, 1), blurRadius: 3, spreadRadius: 0),
    BoxShadow(color: Color(0x1A1A1A1A), offset: Offset(0, 2), blurRadius: 4, spreadRadius: -1),
  ];

  static const List<BoxShadow> shadowLg = [
    BoxShadow(color: Color(0x1A1A1A1A), offset: Offset(0, 1), blurRadius: 3, spreadRadius: 0),
    BoxShadow(color: Color(0x1A1A1A1A), offset: Offset(0, 4), blurRadius: 6, spreadRadius: -1),
  ];

  static const List<BoxShadow> shadowXl = [
    BoxShadow(color: Color(0x1A1A1A1A), offset: Offset(0, 1), blurRadius: 3, spreadRadius: 0),
    BoxShadow(color: Color(0x1A1A1A1A), offset: Offset(0, 8), blurRadius: 10, spreadRadius: -1),
  ];

  static const List<BoxShadow> shadow2xl = [
    BoxShadow(color: Color(0x401A1A1A), offset: Offset(0, 1), blurRadius: 3, spreadRadius: 0),
  ];

  /// Default card / surface elevation.
  static const List<BoxShadow> card = shadowSm;

  /// Authenticated shell content panel — casts onto the accent gutter above and
  /// to the leading side because the panel is flush to the trailing/bottom edges.
  static const List<BoxShadow> shellContentPanel = [
    BoxShadow(color: Color(0x2E1A1A1A), offset: Offset(-8, -5), blurRadius: 10, spreadRadius: -4),
    BoxShadow(color: Color(0x1A1A1A1A), offset: Offset(-3, -2), blurRadius: 8, spreadRadius: -1),
  ];

  /// Exposes the raw shadow color for custom compositions.
  static Color get shadowColor => _shadowColor;
}
