import 'package:flutter/material.dart';

import '../../color_tokens.dart';

/// eCarely variant color palettes — mint-grey clinical dashboard aesthetic.
///
/// Light: pale mint canvas, white cards, teal primary, orange secondary.
/// Dark: deep slate surfaces with boosted teal and amber accents.
abstract final class ECarelyColorTokens {
  static const light = ColorTokens(
    background: Color(0xFFF0F5F3),
    foreground: Color(0xFF111827),
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF111827),
    popover: Color(0xFFFFFFFF),
    popoverForeground: Color(0xFF111827),
    primary: Color(0xFF15847B),
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFFF59E0B),
    secondaryForeground: Color(0xFF111827),
    muted: Color(0xFFF7F9F8),
    mutedForeground: Color(0xFF6B7280),
    accent: Color(0xFFFFFFFF),
    accentForeground: Color(0xFF15847B),
    destructive: Color(0xFFEF4444),
    destructiveForeground: Color(0xFFFFFFFF),
    border: Color(0xFFE5E7EB),
    input: Color(0xFFFFFFFF),
    ring: Color(0xFF15847B),
    chart1: Color(0xFF15847B),
    chart2: Color(0xFFF59E0B),
    chart3: Color(0xFFA5B4FC),
    chart4: Color(0xFF6B7280),
    chart5: Color(0xFF34D399),
    sidebar: Color(0xFFF7F9F8),
    sidebarForeground: Color(0xFF6B7280),
    sidebarPrimary: Color(0xFF15847B),
    sidebarPrimaryForeground: Color(0xFFFFFFFF),
    sidebarAccent: Color(0xFFFFFFFF),
    sidebarAccentForeground: Color(0xFF111827),
    sidebarBorder: Color(0xFFE5E7EB),
    sidebarRing: Color(0xFF15847B),
  );

  static const dark = ColorTokens(
    background: Color(0xFF0F172A),
    foreground: Color(0xFFF9FAFB),
    card: Color(0xFF1E293B),
    cardForeground: Color(0xFFF9FAFB),
    popover: Color(0xFF1E293B),
    popoverForeground: Color(0xFFF9FAFB),
    primary: Color(0xFF1A9A8F),
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFFFBBF24),
    secondaryForeground: Color(0xFF111827),
    muted: Color(0xFF334155),
    mutedForeground: Color(0xFF94A3B8),
    accent: Color(0xFF164E48),
    accentForeground: Color(0xFF5EEAD4),
    destructive: Color(0xFFF87171),
    destructiveForeground: Color(0xFFFFFFFF),
    border: Color(0xFF334155),
    input: Color(0xFF334155),
    ring: Color(0xFF1A9A8F),
    chart1: Color(0xFF1A9A8F),
    chart2: Color(0xFFFBBF24),
    chart3: Color(0xFFA5B4FC),
    chart4: Color(0xFF94A3B8),
    chart5: Color(0xFF34D399),
    sidebar: Color(0xFF1E293B),
    sidebarForeground: Color(0xFF94A3B8),
    sidebarPrimary: Color(0xFF1A9A8F),
    sidebarPrimaryForeground: Color(0xFFFFFFFF),
    sidebarAccent: Color(0xFF334155),
    sidebarAccentForeground: Color(0xFFF9FAFB),
    sidebarBorder: Color(0xFF475569),
    sidebarRing: Color(0xFF1A9A8F),
  );

  static ColorTokens forBrightness(Brightness brightness) => brightness == Brightness.dark ? dark : light;
}
