import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shadow_tokens.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';

/// Visit-page layout constants.
abstract final class VisitPageTokens {
  static const double sectionGap = SpacingTokens.md;
  static const double marginRailWidth = 28;
  static const double summaryTitleWidth = 168;
  static const double metricTileMinWidth = 150;
  static const double subjectiveWatermarkIconSize = 250;
  static const double subjectiveWatermarkOpacity = 0.05;

  static const clinicalSections = <({String abbr, String label})>[
    (abbr: 'C', label: 'Complaint'),
    (abbr: 'H', label: 'History'),
    (abbr: 'E', label: 'Examination'),
    (abbr: 'D', label: 'Diagnosis'),
    (abbr: 'P', label: 'Plan'),
  ];
}

/// Theme-aware styling for visit pages — delegates to [SemanticColors],
/// [ShapeTokens], [TextTheme], [SpacingTokens], and [ShadowTokens].
class VisitTheme {
  VisitTheme._(this._context);

  final BuildContext _context;

  static VisitTheme of(BuildContext context) => VisitTheme._(context);

  SemanticColors get _colors => _context.semanticColors;
  ShapeTokens get _shapes => _context.shapeTokens;
  TextTheme get _text => Theme.of(_context).textTheme;

  // ── Surfaces & ink ────────────────────────────────────────────────────

  Color get ink => _colors.foreground;
  Color get canvas => _colors.background;
  Color get surface => _colors.card;
  Color get tile => _colors.muted;

  // ── Accent & status ───────────────────────────────────────────────────

  Color get pulse => _colors.primary;
  Color get pulseDeep => _colors.ring;
  Color get danger => _colors.destructive;

  // ── Text & lines ──────────────────────────────────────────────────────

  Color get mutedInk => _colors.mutedForeground;
  Color get hairline => _colors.border;
  Color get hairlineSoft => _colors.border.withValues(alpha: 0.55);

  // ── Shape & elevation ─────────────────────────────────────────────────

  double get panelRadius => _shapes.lg;
  double get tileRadius => _shapes.md;

  List<BoxShadow> get panelShadow => ShadowTokens.card;

  /// Left-to-right pulse wash used on subjective intake cards (Complaint, History).
  LinearGradient get pulseCardGradient => LinearGradient(
    colors: [pulse.withValues(alpha: 0.12), pulse.withValues(alpha: 0)],
    stops: const [0, 0.32],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Left-to-right primary wash for the encounter header shell.
  LinearGradient get headerGradient => LinearGradient(
    colors: [Color.alphaBlend(pulse.withValues(alpha: 0.14), surface), surface],
    stops: const [0, 0.55],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  Color get subjectiveWatermark => pulse.withValues(alpha: VisitPageTokens.subjectiveWatermarkOpacity);

  // ── Typography ──────────────────────────────────────────────────────────

  TextStyle title({Color? color, double? size}) =>
      _text.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: size, color: color ?? ink) ??
      TextStyle(fontSize: size ?? 15, fontWeight: FontWeight.w600, color: color ?? ink);

  TextStyle eyebrow({Color? color, double? size}) =>
      _text.labelSmall?.copyWith(
        fontSize: size,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
        color: color ?? mutedInk,
      ) ??
      TextStyle(fontSize: size ?? 10, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: color ?? mutedInk);

  TextStyle readout({Color? color, double? size}) =>
      _text.labelMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: size, color: color ?? ink) ??
      TextStyle(fontSize: size ?? 14, fontWeight: FontWeight.w600, color: color ?? ink);

  TextStyle body({Color? color, double? size, FontWeight weight = FontWeight.w400}) =>
      _text.bodyMedium?.copyWith(fontSize: size, fontWeight: weight, color: color ?? ink) ??
      TextStyle(fontSize: size ?? 12.5, fontWeight: weight, color: color ?? ink);

  TextStyle bodyStrong({Color? color, double? size}) => body(color: color, size: size, weight: FontWeight.w600);

  TextStyle caption({Color? color, double? size}) =>
      _text.bodySmall?.copyWith(fontSize: size, color: color ?? mutedInk) ??
      TextStyle(fontSize: size ?? 11, color: color ?? mutedInk);
}

/// Convenience accessor for [VisitTheme] from a [BuildContext].
extension VisitThemeContext on BuildContext {
  VisitTheme get visitTheme => VisitTheme.of(this);
}

/// Section identity for visit panels.
enum VisitPanelKind {
  subjective(Icons.record_voice_over_outlined),
  examination(Icons.medical_services_outlined),
  diagnosis(Icons.medical_information_outlined),
  plan(Icons.assignment_outlined),
  vitalSigns(Icons.monitor_heart_outlined),
  treatment(Icons.medication_outlined),
  investigation(Icons.biotech_outlined),
  attachment(Icons.attach_file_rounded),
  allergy(Icons.coronavirus_outlined),
  currentMedication(Icons.medication_liquid_outlined),
  chronicCondition(Icons.healing_outlined),
  investigationResult(Icons.science_outlined);

  const VisitPanelKind(this.icon);
  final IconData icon;
}
