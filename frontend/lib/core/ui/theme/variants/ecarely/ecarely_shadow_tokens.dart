import 'package:flutter/material.dart';

/// eCarely variant shadows — soft diffused elevation for light, subtle glow for dark.
abstract final class ECarelyShadowTokens {
  static const List<BoxShadow> lightCard = [
    BoxShadow(color: Color(0x14111827), offset: Offset(0, 4), blurRadius: 24, spreadRadius: 0),
    BoxShadow(color: Color(0x0A15847B), offset: Offset(0, 8), blurRadius: 32, spreadRadius: -4),
  ];

  static const List<BoxShadow> darkCard = [
    BoxShadow(color: Color(0x14FFFFFF), offset: Offset(0, 0), blurRadius: 1, spreadRadius: 0),
    BoxShadow(color: Color(0x0A1A9A8F), offset: Offset(0, 4), blurRadius: 16, spreadRadius: 0),
  ];

  static Color cardShadowColor(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0x331A9A8F) : const Color(0x1A15847B);

  static double get cardElevation => 3;
}
