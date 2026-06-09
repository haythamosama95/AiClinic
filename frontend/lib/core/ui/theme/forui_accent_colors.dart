import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'color_tokens.dart';

/// Accent palette exposed through [FColors.extensions] for forui hover surfaces.
@immutable
class FAccentColors extends ThemeExtension<FAccentColors> {
  const FAccentColors({required this.accent, required this.accentForeground});

  final Color accent;
  final Color accentForeground;

  factory FAccentColors.fromTokens(ColorTokens tokens) {
    return FAccentColors(accent: tokens.accent, accentForeground: tokens.accentForeground);
  }

  @override
  FAccentColors copyWith({Color? accent, Color? accentForeground}) {
    return FAccentColors(accent: accent ?? this.accent, accentForeground: accentForeground ?? this.accentForeground);
  }

  @override
  FAccentColors lerp(ThemeExtension<FAccentColors>? other, double t) {
    if (other is! FAccentColors) {
      return this;
    }

    return FAccentColors(
      accent: Color.lerp(accent, other.accent, t)!,
      accentForeground: Color.lerp(accentForeground, other.accentForeground, t)!,
    );
  }
}

/// Reads [FAccentColors] from forui [FColors].
extension FColorsAccent on FColors {
  FAccentColors get accentColors => extension<FAccentColors>();
}
