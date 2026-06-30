import 'package:flutter/material.dart';

import '../../color_tokens.dart';

/// Med Spectra variant color palettes — soft UI medical dashboard aesthetic.
///
/// Light: lavender-gray canvas, white cards, vibrant purple primary.
/// Dark: deep navy surfaces with boosted accent saturation.
abstract final class MedSpectraColorTokens {
  static const light = ColorTokens(
    background: Color(0xFFF4F7FE),
    foreground: Color(0xFF2D3748),
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF2D3748),
    popover: Color(0xFFFFFFFF),
    popoverForeground: Color(0xFF2D3748),
    primary: Color(0xFF6347D1),
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFF60A5FA),
    secondaryForeground: Color(0xFFFFFFFF),
    muted: Color(0xFFEDF2F7),
    mutedForeground: Color(0xFF718096),
    accent: Color(0xFFF4F0FF),
    accentForeground: Color(0xFF6347D1),
    destructive: Color(0xFFF87171),
    destructiveForeground: Color(0xFFFFFFFF),
    border: Color(0xFFE2E8F0),
    input: Color(0xFFEDF2F7),
    ring: Color(0xFF6347D1),
    chart1: Color(0xFF6347D1),
    chart2: Color(0xFF60A5FA),
    chart3: Color(0xFF4ADE80),
    chart4: Color(0xFFF87171),
    chart5: Color(0xFF9F8AE8),
    sidebar: Color(0xFFFFFFFF),
    sidebarForeground: Color(0xFF718096),
    sidebarPrimary: Color(0xFF6347D1),
    sidebarPrimaryForeground: Color(0xFFFFFFFF),
    sidebarAccent: Color(0xFFF4F0FF),
    sidebarAccentForeground: Color(0xFF6347D1),
    sidebarBorder: Color(0xFFE2E8F0),
    sidebarRing: Color(0xFF6347D1),
  );

  static const dark = ColorTokens(
    background: Color(0xFF111827),
    foreground: Color(0xFFF9FAFB),
    card: Color(0xFF1F2937),
    cardForeground: Color(0xFFF9FAFB),
    popover: Color(0xFF1F2937),
    popoverForeground: Color(0xFFF9FAFB),
    primary: Color(0xFF7C5FE6),
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFF60A5FA),
    secondaryForeground: Color(0xFFFFFFFF),
    muted: Color(0xFF374151),
    mutedForeground: Color(0xFF9CA3AF),
    accent: Color(0xFF2D2647),
    accentForeground: Color(0xFFC4B5FD),
    destructive: Color(0xFFF87171),
    destructiveForeground: Color(0xFFFFFFFF),
    border: Color(0xFF374151),
    input: Color(0xFF374151),
    ring: Color(0xFF7C5FE6),
    chart1: Color(0xFF7C5FE6),
    chart2: Color(0xFF60A5FA),
    chart3: Color(0xFF4ADE80),
    chart4: Color(0xFFF87171),
    chart5: Color(0xFFA78BFA),
    sidebar: Color(0xFF1F2937),
    sidebarForeground: Color(0xFF9CA3AF),
    sidebarPrimary: Color(0xFF7C5FE6),
    sidebarPrimaryForeground: Color(0xFFFFFFFF),
    sidebarAccent: Color(0xFF312E81),
    sidebarAccentForeground: Color(0xFFC4B5FD),
    sidebarBorder: Color(0xFF374151),
    sidebarRing: Color(0xFF7C5FE6),
  );

  static ColorTokens forBrightness(Brightness brightness) => brightness == Brightness.dark ? dark : light;
}
