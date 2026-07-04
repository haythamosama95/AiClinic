import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/tokens/app_radii.dart';

/// The Signal signature motif tokens (not the widget).
abstract final class AppSignal {
  static const double thickness = 2;
  static const double thicknessHero = 3;
  static const double radius = AppRadii.full;

  static List<BoxShadow> glow(Color color) => [
    BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8),
  ];
}
