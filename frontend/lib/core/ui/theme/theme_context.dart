import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

extension AppThemeContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;

  AppTypography get typography {
    final base = Theme.of(this).extension<AppTypography>()!;
    final isArabic =
        Directionality.of(this) == TextDirection.rtl ||
        Localizations.localeOf(this).languageCode == 'ar';
    return base.forScript(isArabic);
  }
}
