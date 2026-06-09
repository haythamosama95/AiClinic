import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Border-radius scale exposed through [ThemeExtension].
@immutable
class ShapeTokens extends ThemeExtension<ShapeTokens> {
  const ShapeTokens({required this.sm, required this.md, required this.lg, required this.xl});

  final double sm;
  final double md;
  final double lg;
  final double xl;

  @override
  ShapeTokens copyWith({double? sm, double? md, double? lg, double? xl}) {
    return ShapeTokens(sm: sm ?? this.sm, md: md ?? this.md, lg: lg ?? this.lg, xl: xl ?? this.xl);
  }

  @override
  ShapeTokens lerp(ThemeExtension<ShapeTokens>? other, double t) {
    if (other is! ShapeTokens) {
      return this;
    }

    return ShapeTokens(
      sm: lerpDouble(sm, other.sm, t)!,
      md: lerpDouble(md, other.md, t)!,
      lg: lerpDouble(lg, other.lg, t)!,
      xl: lerpDouble(xl, other.xl, t)!,
    );
  }
}

/// Convenience accessor for [ShapeTokens] from a [BuildContext].
///
/// [ShapeTokens] must be registered on [ThemeData.extensions] — see [AppTheme].
extension ShapeTokensContext on BuildContext {
  ShapeTokens get shapeTokens {
    final tokens = Theme.of(this).extension<ShapeTokens>();
    assert(tokens != null, 'ShapeTokens is missing from ThemeData.extensions. Register it in AppTheme._build.');
    return tokens ?? const ShapeTokens(sm: 4, md: 6, lg: 8, xl: 12);
  }
}
