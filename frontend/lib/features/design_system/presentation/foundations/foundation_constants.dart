import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';

/// Foundation showcase section metadata and token lists.
class FoundationNavSection {
  const FoundationNavSection({required this.id, required this.label});

  final String id;
  final String label;
}

const foundationSections = <FoundationNavSection>[
  FoundationNavSection(id: 'colors', label: 'Color'),
  FoundationNavSection(id: 'typography', label: 'Typography'),
  FoundationNavSection(id: 'spacing', label: 'Spacing & elevation'),
  FoundationNavSection(id: 'motion', label: 'Motion'),
  FoundationNavSection(id: 'signal', label: 'The Signal'),
];

class FoundationColorPair {
  const FoundationColorPair({
    required this.label,
    required this.fg,
    required this.bg,
    required this.darkFg,
    required this.darkBg,
  });

  final String label;
  final Color fg;
  final Color bg;
  final Color darkFg;
  final Color darkBg;
}

const colorPairs = <FoundationColorPair>[
  FoundationColorPair(
    label: 'Primary text',
    fg: Color(0xFF1A2029),
    bg: Color(0xFFFAFBFC),
    darkFg: Color(0xFFE6EBF2),
    darkBg: Color(0xFF0E1116),
  ),
  FoundationColorPair(
    label: 'Secondary text',
    fg: Color(0xFF55606D),
    bg: Color(0xFFFAFBFC),
    darkFg: Color(0xFFA9B4C0),
    darkBg: Color(0xFF0E1116),
  ),
  FoundationColorPair(
    label: 'Action primary',
    fg: Color(0xFFFFFFFF),
    bg: Color(0xFF0B7075),
    darkFg: Color(0xFF0E1116),
    darkBg: Color(0xFF0E8A8F),
  ),
  FoundationColorPair(
    label: 'AI action',
    fg: Color(0xFFFFFFFF),
    bg: Color(0xFF573FD1),
    darkFg: Color(0xFF0E1116),
    darkBg: Color(0xFF6A54E6),
  ),
  FoundationColorPair(
    label: 'Success',
    fg: Color(0xFF0F5E34),
    bg: Color(0xFFE7F6ED),
    darkFg: Color(0xFF5FD495),
    darkBg: Color(0xFF0E2A1B),
  ),
  FoundationColorPair(
    label: 'Warning',
    fg: Color(0xFF855009),
    bg: Color(0xFFFBF1DF),
    darkFg: Color(0xFFE9B45A),
    darkBg: Color(0xFF2E2109),
  ),
  FoundationColorPair(
    label: 'Danger',
    fg: Color(0xFF9A2828),
    bg: Color(0xFFFBECEC),
    darkFg: Color(0xFFF08A8A),
    darkBg: Color(0xFF2E1414),
  ),
  FoundationColorPair(
    label: 'Info',
    fg: Color(0xFF164FAB),
    bg: Color(0xFFE8F0FE),
    darkFg: Color(0xFF7FB0FB),
    darkBg: Color(0xFF0F1F3A),
  ),
];

const spacingTokens = <String>[
  '0',
  'px',
  '0.5',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '8',
  '10',
  '12',
  '16',
  '20',
  '24',
];

const radiusTokens = <String>['sm', 'md', 'lg', 'xl', '2xl', 'full'];

const elevationTokens = <String>['0', '1', '2', '3'];

const motionPresetList = <AppMotionPreset>[
  AppMotionPreset.fade,
  AppMotionPreset.fadeScale,
  AppMotionPreset.slideUp,
  AppMotionPreset.slideInline,
  AppMotionPreset.modal,
  AppMotionPreset.command,
  AppMotionPreset.rowEnter,
];

String motionPresetLabel(AppMotionPreset preset) {
  return switch (preset) {
    AppMotionPreset.fade => 'fade',
    AppMotionPreset.fadeScale => 'fade-scale',
    AppMotionPreset.slideUp => 'slide-up',
    AppMotionPreset.slideInline => 'slide-inline',
    AppMotionPreset.modal => 'modal',
    AppMotionPreset.command => 'command',
    AppMotionPreset.rowEnter => 'row-enter',
  };
}

const typographyScaleRows = <(String token, String size)>[
  ('display-lg', '32/40'),
  ('display', '28/36'),
  ('h1', '24/32'),
  ('h2', '20/28'),
  ('h3', '18/26'),
  ('title', '16/24'),
  ('body-lg', '15/24'),
  ('body', '14/22'),
  ('body-sm', '13/20'),
  ('caption', '12/16'),
  ('overline', '11/16'),
  ('mono', '13/20'),
];

/// Responsive breakpoints aligned with the web reference (`sm` / `lg`).
abstract final class FoundationBreakpoints {
  static const sm = 640.0;
  static const lg = 1024.0;

  static int gridColumns(double width, {required int smCols, required int lgCols}) {
    if (width >= lg) return lgCols;
    if (width >= sm) return smCols;
    return 1;
  }
}
