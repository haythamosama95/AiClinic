import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Ergonomic accessors for design-system [ThemeExtension]s.
extension AppThemeContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  AppElevation get elevation => Theme.of(this).extension<AppElevation>()!;
  AppTypography get typography => Theme.of(this).extension<AppTypography>()!;

  bool get isRtl => Directionality.of(this) == TextDirection.rtl;
}
