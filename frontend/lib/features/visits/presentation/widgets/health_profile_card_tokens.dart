import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';

/// Health profile card (right column on Intake) layout constants.
abstract final class HealthProfileCardTokens {
  // Add card-specific layout constants here when needed.
}

/// Theme-aware styling for the health profile card — mirrors [VisitTheme] surface tokens
/// so the right-column gradient can be tuned independently from subjective intake cards.
class HealthProfileCardTheme {
  HealthProfileCardTheme._(this._context);

  final BuildContext _context;

  static HealthProfileCardTheme of(BuildContext context) => HealthProfileCardTheme._(context);

  SemanticColors get _colors => _context.semanticColors;

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
}

/// Convenience accessor for [HealthProfileCardTheme] from a [BuildContext].
extension HealthProfileCardThemeContext on BuildContext {
  HealthProfileCardTheme get healthProfileCardTheme => HealthProfileCardTheme.of(this);
}
