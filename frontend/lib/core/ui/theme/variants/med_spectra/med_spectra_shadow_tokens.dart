import 'package:flutter/material.dart';

/// Med Spectra variant shadows — soft diffused elevation for light, subtle glow for dark.
abstract final class MedSpectraShadowTokens {
  static const List<BoxShadow> lightCard = [
    BoxShadow(color: Color(0x142D3748), offset: Offset(0, 4), blurRadius: 24, spreadRadius: 0),
    BoxShadow(color: Color(0x0A6347D1), offset: Offset(0, 8), blurRadius: 32, spreadRadius: -4),
  ];

  static const List<BoxShadow> darkCard = [
    BoxShadow(color: Color(0x14FFFFFF), offset: Offset(0, 0), blurRadius: 1, spreadRadius: 0),
    BoxShadow(color: Color(0x0A7C5FE6), offset: Offset(0, 4), blurRadius: 16, spreadRadius: 0),
  ];

  static Color cardShadowColor(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0x337C5FE6) : const Color(0x1A6347D1);

  static double get cardElevation => 3;
}
