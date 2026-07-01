import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Health profile card (right column on Intake) layout constants.
abstract final class HealthProfileCardTokens {
  static const double shellIconSize = 20;
  static const double sectionIconSize = 18;
  static const double sectionWatermarkIconSize = 150;
  static const double sectionWatermarkOpacity = 0.07;
  static const double addIconSize = 20;
  static const double addButtonIconSize = 16;
  static const double tileActionIconSize = 16;
  static const double gridTileExtent = 48;
}

/// Theme-aware styling for the health profile card — mirrors [VisitTheme] surface tokens
/// so the right-column gradient and typography can be tuned independently from subjective intake cards.
class HealthProfileCardTheme {
  HealthProfileCardTheme._(this._context);

  final BuildContext _context;

  static HealthProfileCardTheme of(BuildContext context) => HealthProfileCardTheme._(context);

  SemanticColors get _colors => _context.semanticColors;
  VisitTheme get _visit => VisitTheme.of(_context);

  // ── Accent ────────────────────────────────────────────────────────────

  Color get pulse => _colors.primary;

  // ── Card wash ───────────────────────────────────────────────────────────

  /// Left-to-right pulse wash on the health profile card shell.
  LinearGradient get pulseCardGradient => LinearGradient(
    colors: [pulse.withValues(alpha: 0.05), pulse.withValues(alpha: 0)],
    stops: const [0, 0.15],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // ── Typography ────────────────────────────────────────────────────────

  TextStyle get shellTitle => _visit.title();

  TextStyle get shellSubtitle => _visit.caption(size: 13);

  TextStyle sectionTitle(Color accent) => _visit.bodyStrong(size: 13, color: accent);

  TextStyle countBadge(Color accent) => _visit.caption(size: 11, color: accent);

  TextStyle get itemLabel => _visit.bodyStrong(size: 13);

  TextStyle get emptyMessage => _visit.caption();

  TextStyle errorMessage(Color color) => _visit.caption(color: color);

  Color sectionWatermark(Color accent) => accent.withValues(alpha: HealthProfileCardTokens.sectionWatermarkOpacity);
}

/// Convenience accessor for [HealthProfileCardTheme] from a [BuildContext].
extension HealthProfileCardThemeContext on BuildContext {
  HealthProfileCardTheme get healthProfileCardTheme => HealthProfileCardTheme.of(this);
}
