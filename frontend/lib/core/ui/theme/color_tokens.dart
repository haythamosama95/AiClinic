import 'package:flutter/material.dart';

/// Raw semantic color values for a single brightness variant.
///
/// Mirrors the CSS custom properties from the Tailwind v4 theme (`:root` / `.dark`).
@immutable
class ColorTokens {
  const ColorTokens({
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.popover,
    required this.popoverForeground,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.accentForeground,
    required this.destructive,
    required this.destructiveForeground,
    required this.border,
    required this.input,
    required this.ring,
    required this.chart1,
    required this.chart2,
    required this.chart3,
    required this.chart4,
    required this.chart5,
    required this.sidebar,
    required this.sidebarForeground,
    required this.sidebarPrimary,
    required this.sidebarPrimaryForeground,
    required this.sidebarAccent,
    required this.sidebarAccentForeground,
    required this.sidebarBorder,
    required this.sidebarRing,
  });

  final Color background;
  final Color foreground;
  final Color card;
  final Color cardForeground;
  final Color popover;
  final Color popoverForeground;
  final Color primary;
  final Color primaryForeground;
  final Color secondary;
  final Color secondaryForeground;
  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color accentForeground;
  final Color destructive;
  final Color destructiveForeground;
  final Color border;
  final Color input;
  final Color ring;
  final Color chart1;
  final Color chart2;
  final Color chart3;
  final Color chart4;
  final Color chart5;
  final Color sidebar;
  final Color sidebarForeground;
  final Color sidebarPrimary;
  final Color sidebarPrimaryForeground;
  final Color sidebarAccent;
  final Color sidebarAccentForeground;
  final Color sidebarBorder;
  final Color sidebarRing;

  /// Light theme palette (`:root`).
  static const light = ColorTokens(
    background: Color(0xFFE8EBED),
    foreground: Color(0xFF333333),
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF333333),
    popover: Color(0xFFFFFFFF),
    popoverForeground: Color(0xFF333333),
    primary: Color(0xFFDF6035),
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFF2F4B79),
    secondaryForeground: Color(0xFFFFFFFF),
    muted: Color(0xFFF9FAFB),
    mutedForeground: Color(0xFF6B7280),
    accent: Color(0xFFD6E4F0),
    accentForeground: Color(0xFF1E3A8A),
    destructive: Color(0xFFEF4444),
    destructiveForeground: Color(0xFFFFFFFF),
    border: Color(0xFFCCCCCC),
    input: Color(0xFFF4F5F7),
    ring: Color(0xFFE05D38),
    chart1: Color(0xFF7399BF),
    chart2: Color(0xFFE16F41),
    chart3: Color(0xFFD54450),
    chart4: Color(0xFFE2B146),
    chart5: Color(0xFF3C4C76),
    sidebar: Color(0xFFDDDFE2),
    sidebarForeground: Color(0xFF333333),
    sidebarPrimary: Color(0xFFE05D38),
    sidebarPrimaryForeground: Color(0xFFFFFFFF),
    sidebarAccent: Color(0xFFD6E4F0),
    sidebarAccentForeground: Color(0xFF1E3A8A),
    sidebarBorder: Color(0xFFE5E7EB),
    sidebarRing: Color(0xFFE05D38),
  );

  /// Dark theme palette (`.dark`).
  static const dark = ColorTokens(
    background: Color(0xFF1A1A1A),
    foreground: Color(0xFFE5E5E5),
    card: Color(0xFF202020),
    cardForeground: Color(0xFFE5E5E5),
    popover: Color(0xFF202020),
    popoverForeground: Color(0xFFE5E5E5),
    primary: Color(0xFFDF6035),
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFF284167),
    secondaryForeground: Color(0xFFE5E5E5),
    muted: Color(0xFF2A2A2A),
    mutedForeground: Color(0xFF808080),
    accent: Color(0xFF2A3656),
    accentForeground: Color(0xFFBFDBFE),
    destructive: Color(0xFFEF4444),
    destructiveForeground: Color(0xFFFFFFFF),
    border: Color(0xFF353535),
    input: Color(0xFF303030),
    ring: Color(0xFFE05D38),
    chart1: Color(0xFF85A6C7),
    chart2: Color(0xFFE16F41),
    chart3: Color(0xFFD54450),
    chart4: Color(0xFFE2B146),
    chart5: Color(0xFF3C4C76),
    sidebar: Color(0xFF1F1F1F),
    sidebarForeground: Color(0xFFE5E5E5),
    sidebarPrimary: Color(0xFFE05D38),
    sidebarPrimaryForeground: Color(0xFFFFFFFF),
    sidebarAccent: Color(0xFF2A3656),
    sidebarAccentForeground: Color(0xFFBFDBFE),
    sidebarBorder: Color(0xFF353535),
    sidebarRing: Color(0xFFE05D38),
  );

  static ColorTokens forBrightness(Brightness brightness) => brightness == Brightness.dark ? dark : light;
}
